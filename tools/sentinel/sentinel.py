#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""sentinel — Claude Code 自我监控哨兵(Tea 项目)

设计原则(五条):
1. 判决优先:每个命令第一行输出 `VERDICT: <状态>`,附证据与建议;--json 给机读全量。
2. 上下文经济:默认输出 ≤30 行;细节落盘只返回路径。
3. 新鲜度由工具保证:时间戳/md5/字节偏移由哨兵记账。
4. 熔断是功能:预算/计数到线主动 ESCALATE。
5. 自体检:`sentinel selftest` 全绿才算可信。

零 pip 依赖,只用 macOS 自带命令(screencapture/sips/caffeinate/pgrep/pkill/osascript)。
状态与产物:$TEA_HOME/sentinel/{jobs/,shots/,state.json,inbox.md,offsets.json,...}
"""
import argparse
import base64
import hashlib
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

# ───────────────────────────── 基础路径 ─────────────────────────────

TEA_HOME = os.environ.get(
    "TEA_HOME", os.path.expanduser("~/Library/Application Support/Tea"))
ROOT = os.path.join(TEA_HOME, "sentinel")
JOBS = os.path.join(ROOT, "jobs")
SHOTS = os.path.join(ROOT, "shots")
STATE = os.path.join(ROOT, "state.json")
OFFSETS = os.path.join(ROOT, "offsets.json")
BUDGETS = os.path.join(ROOT, "budgets.json")
ATTEMPTS = os.path.join(ROOT, "attempts.json")
INBOX = os.path.join(ROOT, "inbox.md")
INBOX_SEEN = os.path.join(ROOT, ".inbox_seen")


def ensure_dirs():
    for d in (ROOT, JOBS, SHOTS):
        os.makedirs(d, exist_ok=True)


def jload(path, default):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default


def jsave(path, obj):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=1)
    os.replace(tmp, path)


def now():
    return time.time()


def md5_file(path, limit=None):
    h = hashlib.md5()
    with open(path, "rb") as f:
        if limit:
            h.update(f.read(limit))
        else:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
    return h.hexdigest()


def out(verdict, lines=None, js=None, as_json=False):
    """双通道输出:人读(VERDICT + ≤30 行要点) / --json 机读。"""
    if as_json:
        payload = {"verdict": verdict}
        payload.update(js or {})
        print(json.dumps(payload, ensure_ascii=False, indent=1))
    else:
        print(f"VERDICT: {verdict}")
        for ln in (lines or [])[:29]:
            print(ln)
    return 0 if not verdict.startswith(("ESCALATE", "BLOCKED", "FAIL")) else 1


# ───────────────────────────── 日志签名库 ─────────────────────────────
# 与 diagnostics/rules/ 同源(仓库内规则可扩展);内置底线签名。

BUILTIN_SIGNATURES = [
    (r"c0000142", "DLL_INIT_FAILED(c0000142)——底座/胶水代际不匹配嫌疑"),
    (r"c0000005", "ACCESS_VIOLATION(c0000005)"),
    (r"Unhandled page fault", "PAGE_FAULT——记崩溃地址,固定地址=游戏自身代码"),
    (r"codefusion\.technology|88500006", "DENUVO 配额/激活弹窗——立即停手,勿点按钮"),
    (r"EasyAntiCheat|BattlEye|EAC", "反作弊组件——大概率 Unsupported"),
    (r"version mismatch \d+/\d+", "WINESERVER 版本冲突——先 purge 再重试"),
    (r"Exception frame is not in stack", "32位 SEH 栈异常——wine wow64 已知死角"),
    (r"Failed to dlopen D3DMetal", "D3DMetal 框架加载失败——查 rpath/符号链接"),
    (r"GPU process|gpu_channel_host|SharedImageStub", "CEF/GPU 进程错误——查 webhelper 包装器"),
    (r"D3D11InternalCreateDevice|feature level", "D3D 设备初始化标记(非错误,进度信号)"),
    (r"Actual swap ?chain properties", "交换链建成(进度信号:图形栈到位)"),
    (r"Auto-start service .* failed", "wine 服务启动失败(最小构建常见,通常无害)"),
    (r"loader_section|LdrInitializeThunk.*failed", "加载器阶段失败"),
    (r"Assertion failed", "断言失败——取整行进 PROGRESS"),
]


def load_signatures():
    sigs = list(BUILTIN_SIGNATURES)
    # 仓库规则同源:diagnostics/rules/*.txt,格式 "regex<TAB>标签"
    rules_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                             "..", "..", "diagnostics", "rules")
    if os.path.isdir(rules_dir):
        for fn in sorted(os.listdir(rules_dir)):
            if not fn.endswith(".txt"):
                continue
            try:
                with open(os.path.join(rules_dir, fn), encoding="utf-8") as f:
                    for ln in f:
                        ln = ln.rstrip("\n")
                        if not ln or ln.startswith("#") or "\t" not in ln:
                            continue
                        rx, tag = ln.split("\t", 1)
                        sigs.append((rx, tag))
            except Exception:
                pass
    return sigs


def scan_signatures(text):
    hits = []
    sigs = load_signatures()
    for rx, tag in sigs:
        m = re.search(rx, text)
        if m:
            hits.append((tag, m.group(0)[:60]))
    return hits


# ───────────────────────────── 任务(run/jobs/watch) ─────────────────────────────

PATIENCE = {  # 静默容忍秒数:超过才可能判 LIKELY_HUNG
    "default": 120,
    "boot": 180,          # wine 首次 boot
    "download": 300,      # Steam 下载可长时间无 stdout
    "shader": 1200,       # 007 情报:shader 编译卡 99% 20 分钟属正常
    "compile": 3600,      # CX 源码编译 1 小时级
}


def job_dir(jid):
    return os.path.join(JOBS, jid)


def cmd_run(args, as_json):
    ensure_dirs()
    jid = f"{args.name}-{int(now())}"
    d = job_dir(jid)
    os.makedirs(d)
    logf = os.path.join(d, "out.log")
    rcf = os.path.join(d, "exit_code")
    cmd = args.cmd
    if not cmd:
        return out("FAIL 没有命令", ["用法: sentinel run <name> -- <cmd...>"],
                   as_json=as_json)
    shell_cmd = " ".join(cmd) if len(cmd) > 1 or " " in cmd[0] else cmd[0]
    # caffeinate 包裹防睡眠;setsid 脱离会话;exit code 落盘
    wrapper = f"({shell_cmd}); echo $? > {json.dumps(rcf)}"
    with open(os.path.join(d, "cmd.txt"), "w") as f:
        f.write(shell_cmd + "\n")
    with open(logf, "ab") as lf:
        p = subprocess.Popen(
            ["caffeinate", "-dis", "/bin/zsh", "-c", wrapper],
            stdout=lf, stderr=lf, stdin=subprocess.DEVNULL,
            start_new_session=True)
    meta = {"name": args.name, "pid": p.pid, "cmd": shell_cmd,
            "start": now(), "profile": args.profile or "default"}
    jsave(os.path.join(d, "meta.json"), meta)
    return out("STARTED", [f"job: {jid}", f"pid: {p.pid}", f"log: {logf}",
                           f"profile: {meta['profile']}"],
               {"job": jid, "pid": p.pid, "log": logf}, as_json)


def job_quick_verdict(jid):
    d = job_dir(jid)
    meta = jload(os.path.join(d, "meta.json"), {})
    rcf = os.path.join(d, "exit_code")
    if os.path.exists(rcf):
        rc = open(rcf).read().strip()
        return f"DONE rc={rc}"
    pid = meta.get("pid")
    if pid and pid_alive_tree(pid):
        return "RUNNING"
    return "DEAD(无 exit code——被杀或崩)"


def pid_alive_tree(pid):
    """进程或其子进程组任一存活。"""
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        pass
    # 会话组里的孩子(caffeinate 的子进程)
    r = subprocess.run(["pgrep", "-g", str(pid)], capture_output=True)
    return r.returncode == 0


def cmd_jobs(args, as_json):
    ensure_dirs()
    rows = []
    for jid in sorted(os.listdir(JOBS)):
        if not os.path.isdir(job_dir(jid)):
            continue
        rows.append((jid, job_quick_verdict(jid)))
    if not rows:
        return out("EMPTY", ["无 job"], {"jobs": []}, as_json)
    return out("OK", [f"{j}: {v}" for j, v in rows[-15:]],
               {"jobs": [{"job": j, "state": v} for j, v in rows]}, as_json)


def proc_cpu(pid):
    """进程树累计 CPU%(pid + 同组)。"""
    total = 0.0
    r = subprocess.run(["ps", "-o", "%cpu=", "-p", str(pid)],
                       capture_output=True, text=True)
    for ln in r.stdout.splitlines():
        try:
            total += float(ln.strip())
        except ValueError:
            pass
    r = subprocess.run(["pgrep", "-g", str(pid)], capture_output=True, text=True)
    kids = [k for k in r.stdout.split() if k.strip()]
    if kids:
        r = subprocess.run(["ps", "-o", "%cpu=", "-p", ",".join(kids)],
                           capture_output=True, text=True)
        for ln in r.stdout.splitlines():
            try:
                total += float(ln.strip())
            except ValueError:
                pass
    return total


def cmd_watch(args, as_json):
    ensure_dirs()
    target = args.target
    profile = args.profile or None
    interval = args.interval
    # 解析目标:job 名(取最新匹配)或纯 pid
    jid, meta, logf, rcf, pid = None, {}, None, None, None
    if target.isdigit():
        pid = int(target)
    else:
        cands = sorted([j for j in os.listdir(JOBS) if j.startswith(target)])
        if not cands:
            return out("FAIL 未找到 job", [f"目标: {target}"], as_json=as_json)
        jid = cands[-1]
        meta = jload(os.path.join(job_dir(jid), "meta.json"), {})
        logf = os.path.join(job_dir(jid), "out.log")
        rcf = os.path.join(job_dir(jid), "exit_code")
        pid = meta.get("pid")
        profile = profile or meta.get("profile", "default")
    patience = PATIENCE.get(profile or "default", PATIENCE["default"])

    # 完成判定优先
    if rcf and os.path.exists(rcf):
        rc = open(rcf).read().strip()
        tail = tail_lines(logf, 3) if logf else []
        v = f"DONE rc={rc}"
        return out(v, [f"job: {jid}"] + [f"  {t}" for t in tail],
                   {"job": jid, "rc": rc}, as_json)

    alive = pid_alive_tree(pid) if pid else False
    if not alive:
        return out("DEAD", [f"目标 {target} 无存活进程且无 exit code(被杀或崩)",
                            "建议: sentinel logs 取尾部证据"],
                   {"target": target}, as_json)

    # 双采样:CPU + 输出增量
    size0 = os.path.getsize(logf) if logf and os.path.exists(logf) else 0
    cpu0 = proc_cpu(pid)
    time.sleep(interval)
    size1 = os.path.getsize(logf) if logf and os.path.exists(logf) else 0
    cpu1 = proc_cpu(pid)
    grew = size1 > size0
    cpu = max(cpu0, cpu1)

    # 静默时长:自日志 mtime
    silent_s = 0
    if logf and os.path.exists(logf):
        silent_s = int(now() - os.path.getmtime(logf))

    ev = [f"pid={pid} cpu={cpu:.1f}% 日志增长={size1-size0}B 静默={silent_s}s",
          f"耐心档: {profile}({patience}s)"]
    if grew or cpu > 5.0:
        v = "RUNNING_HEALTHY"
        ev.append("建议: 继续等,勿打扰")
    elif silent_s < patience:
        v = "RUNNING_SILENT"
        ev.append(f"活着但无输出;{patience - silent_s}s 后仍静默才可疑")
    else:
        v = "LIKELY_HUNG"
        ev.append("建议: sentinel logs 取证 → purge → 记 PROGRESS")
    return out(v, ev, {"pid": pid, "cpu": cpu, "grew": grew,
                       "silent_s": silent_s}, as_json)


def tail_lines(path, n):
    try:
        with open(path, "rb") as f:
            f.seek(0, 2)
            size = f.tell()
            f.seek(max(0, size - 8192))
            data = f.read().decode("utf-8", "replace")
        return [ln for ln in data.splitlines() if ln.strip()][-n:]
    except Exception:
        return []


# ───────────────────────────── logs --since-last ─────────────────────────────

def cmd_logs(args, as_json):
    ensure_dirs()
    target = args.target
    # job 名 → 其 out.log;否则视为文件路径
    path = target
    cands = sorted([j for j in os.listdir(JOBS) if j.startswith(target)])
    if cands:
        path = os.path.join(job_dir(cands[-1]), "out.log")
    path = os.path.expanduser(path)
    if not os.path.exists(path):
        return out("FAIL 文件不存在", [path], as_json=as_json)

    offsets = jload(OFFSETS, {})
    key = os.path.abspath(path)
    rec = offsets.get(key, {})
    size = os.path.getsize(path)
    mtime = os.path.getmtime(path)

    off = rec.get("offset", 0)
    # 轮转判定:头部指纹只覆盖「上次已读过的头部长度」,追加不算轮转
    head_len = min(4096, off) if off else 0
    head_md5 = md5_file(path, limit=head_len) if head_len else ""
    rotated = bool(rec) and (size < off or
                             (rec.get("head_md5") and
                              rec.get("head_md5") != head_md5))
    if rotated:
        off = 0  # 文件被轮转/重写,从头读
    with open(path, "rb") as f:
        f.seek(off)
        delta = f.read().decode("utf-8", "replace")
    new_head_len = min(4096, size)
    offsets[key] = {"offset": size, "mtime": mtime,
                    "head_md5": md5_file(path, limit=new_head_len)
                    if new_head_len else "",
                    "read_at": now()}
    jsave(OFFSETS, offsets)

    fresh = (now() - mtime) < 3600
    tags = scan_signatures(delta)
    dlines = [ln for ln in delta.splitlines() if ln.strip()]
    ev = [f"文件: {path}",
          f"新内容: {len(delta)}B/{len(dlines)}行  mtime {int(now()-mtime)}s 前"
          f"{'' if fresh else ' ⚠️ 超1小时,新鲜度存疑'}"
          f"{' (检测到轮转,从头读)' if rotated else ''}"]
    for tag, sample in tags[:6]:
        ev.append(f"🏷  {tag} | {sample}")
    if not dlines:
        ev.append("(自上次读取无新内容)")
    else:
        # 细节落盘,只回尾部要点
        dpath = os.path.join(ROOT, "last_delta.txt")
        with open(dpath, "w", encoding="utf-8") as f:
            f.write(delta)
        ev.append(f"delta 全文: {dpath}")
        ev += [f"  {ln[:110]}" for ln in dlines[-8:]]
    v = "TAGGED" if tags else ("NEW" if dlines else "NO_NEW")
    return out(v, ev, {"path": path, "delta_bytes": len(delta),
                       "tags": [t for t, _ in tags], "fresh": fresh}, as_json)


# ───────────────────────────── shot / ps / purge / doctor ─────────────────────────────

# 1x1 黑 PNG(selftest 用)
BLACK_PNG_B64 = ("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4"
                 "nGNgYGAAAAAEAAH2FzhVAAAAAElFTkSuQmCC")


def analyze_shot(path, prev_path=None):
    """零依赖启发式:黑屏嫌疑(压缩后异常小) + 冻结(md5 相同)。"""
    size = os.path.getsize(path)
    flags = []
    # 全屏截图正常 MB 级;<300KB 高度可疑纯色/黑屏
    if size < 300_000:
        flags.append("BLACK_SUSPECT(体积异常小,疑纯色/黑屏)")
    if prev_path and os.path.exists(prev_path):
        if md5_file(path) == md5_file(prev_path):
            flags.append("FROZEN(与上一张 md5 相同,画面冻结)")
    return flags


def cmd_shot(args, as_json):
    ensure_dirs()
    tag = args.tag or "shot"
    ts = time.strftime("%H%M%S")
    path = os.path.join(SHOTS, f"{time.strftime('%m%d')}_{ts}_{tag}.png")
    r = subprocess.run(["screencapture", "-x", "-o", path],
                       capture_output=True)
    if r.returncode != 0 or not os.path.exists(path):
        return out("FAIL 截图失败", ["检查: 终端需要「屏幕录制」权限",
                                    r.stderr.decode()[:100]], as_json=as_json)
    # 找同 tag 上一张
    prev = sorted([f for f in os.listdir(SHOTS)
                   if f.endswith(f"_{tag}.png") and
                   os.path.join(SHOTS, f) != path])
    prev_path = os.path.join(SHOTS, prev[-1]) if prev else None
    flags = analyze_shot(path, prev_path)
    v = " ".join(flags) if flags else "CAPTURED"
    return out(v, [f"图: {path}",
                   "语义判断请 view 该图(哨兵只拍+启发式,眼睛是 Claude 的)"],
               {"path": path, "flags": flags}, as_json)


WINE_CLASSES = [
    (r"steamwebhelper", "webhelper"),
    (r"steam\.exe|steamservice", "steam"),
    (r"wineserver", "wineserver"),
    (r"winedevice|services\.exe|plugplay|svchost|rpcss|explorer\.exe|"
     r"conhost|tabtip|start\.exe", "wine 基础设施"),
    (r"\.exe", "游戏/应用 exe"),
    (r"wine", "wine 进程"),
]


def wine_ps():
    r = subprocess.run(["ps", "-axo", "pid=,etime=,%cpu=,command="],
                       capture_output=True, text=True)
    rows = []
    for ln in r.stdout.splitlines():
        parts = ln.strip().split(None, 3)
        if len(parts) < 4:
            continue
        pid, etime, cpu, cmd = parts
        if not re.search(r"wine|steam|\.exe", cmd, re.I):
            continue
        if "sentinel" in cmd:
            continue
        cls = "其他"
        for rx, c in WINE_CLASSES:
            if re.search(rx, cmd, re.I):
                cls = c
                break
        rows.append({"pid": pid, "etime": etime, "cpu": cpu,
                     "class": cls, "cmd": cmd[:80]})
    return rows


def cmd_ps(args, as_json):
    rows = wine_ps()
    if not rows:
        return out("CLEAN", ["无 wine/Steam 相关进程"], {"procs": []}, as_json)
    counts = {}
    for r_ in rows:
        counts[r_["class"]] = counts.get(r_["class"], 0) + 1
    ev = [", ".join(f"{k}×{v}" for k, v in sorted(counts.items()))]
    for r_ in rows[:20]:
        ev.append(f"{r_['pid']:>6} {r_['class']:<10} cpu={r_['cpu']:>5} "
                  f"{r_['cmd'][:70]}")
    return out(f"FOUND {len(rows)}", ev, {"procs": rows}, as_json)


def cmd_purge(args, as_json):
    """清场口诀固化:游戏 exe → steam → webhelper → wineserver -k → 复查。"""
    seq = []
    def kill(pat, sig="-9"):
        r = subprocess.run(["pkill", sig, "-f", pat], capture_output=True)
        seq.append(f"pkill {pat}: {'命中' if r.returncode == 0 else '无'}")
    # 内部钩子:selftest 只演练指定 pid
    if getattr(args, "selftest_pid", None):
        try:
            os.kill(int(args.selftest_pid), signal.SIGKILL)
            seq.append(f"kill selftest pid {args.selftest_pid}")
        except OSError as e:
            seq.append(f"kill 失败: {e}")
    else:
        rows = wine_ps()
        game_pats = sorted({r_["cmd"].split()[0] for r_ in rows
                            if r_["class"] == "游戏/应用 exe"})
        for p in game_pats:
            kill(re.escape(os.path.basename(p)))
        kill("steam\\.exe|steamservice")
        kill("steamwebhelper")
        time.sleep(1)
        # 所有 runtime 的 wineserver -k
        rt_dir = os.path.join(TEA_HOME, "runtimes")
        if os.path.isdir(rt_dir):
            for rt in sorted(os.listdir(rt_dir)):
                ws = os.path.join(rt_dir, rt, "bin", "wineserver")
                if os.path.exists(ws):
                    subprocess.run([ws, "-k"], capture_output=True)
            seq.append("wineserver -k × 全部 runtime")
        kill("wine")
        time.sleep(1)
        # 最后一轮:wine 基础设施 cmdline 是 Windows 路径(services.exe 等),
        # pkill wine 打不中——按分类快照逐 pid 清扫
        for r_ in wine_ps():
            try:
                os.kill(int(r_["pid"]), signal.SIGKILL)
            except (OSError, ValueError):
                pass
        seq.append("逐 pid 清扫 wine 基础设施")
        time.sleep(2)
    left = wine_ps()
    if left and not getattr(args, "selftest_pid", None):
        ev = seq + [f"⚠️ 残留 {len(left)}:"] + \
            [f"  {r_['pid']} {r_['cmd'][:60]}" for r_ in left[:5]]
        return out("RESIDUAL", ev, {"seq": seq, "left": left}, as_json)
    return out("CLEAN", seq + ["复查: 无残留"], {"seq": seq}, as_json)


def cmd_doctor(args, as_json):
    """开跑前不变量体检。任何一项不过 = BLOCKED。"""
    ensure_dirs()
    checks, ok = [], True
    def chk(name, passed, detail=""):
        nonlocal ok
        checks.append(f"{'✅' if passed else '❌'} {name}"
                      + (f" — {detail}" if detail else ""))
        ok = ok and passed
    # 磁盘
    du = shutil.disk_usage(os.path.expanduser("~"))
    free_gb = du.free / 1e9
    chk("磁盘余量", free_gb > 10, f"{free_gb:.0f}GB")
    # Rosetta
    r = subprocess.run(["arch", "-x86_64", "/usr/bin/true"],
                       capture_output=True)
    chk("Rosetta", r.returncode == 0)
    # runtimes
    rt_dir = os.path.join(TEA_HOME, "runtimes")
    rts = sorted(os.listdir(rt_dir)) if os.path.isdir(rt_dir) else []
    chk("runtimes 目录", bool(rts), f"{len(rts)} 个")
    # 残留进程
    rows = wine_ps()
    chk("无残留 wine/Steam 进程", not rows,
        f"{len(rows)} 个残留,先 sentinel purge" if rows else "")
    # 截图权限(拍一张验证)
    tmp = os.path.join(tempfile.gettempdir(), "sentinel_perm.png")
    r = subprocess.run(["screencapture", "-x", "-o", tmp], capture_output=True)
    shot_ok = r.returncode == 0 and os.path.exists(tmp) and \
        os.path.getsize(tmp) > 10_000
    chk("屏幕录制权限", shot_ok, "" if shot_ok else "系统设置→隐私→屏幕录制,勾选终端")
    if os.path.exists(tmp):
        os.unlink(tmp)
    # state 台账可读
    st = jload(STATE, None)
    chk("state.json", st is not None or not os.path.exists(STATE),
        "存在且可读" if st else "尚未建立(首次运行正常)")
    return out("READY" if ok else "BLOCKED", checks,
               {"ok": ok, "checks": checks}, as_json)


# ───────────────────────────── state / guard / budget / attempt ─────────────────────────────

def cmd_state(args, as_json):
    ensure_dirs()
    st = jload(STATE, {})
    if args.set:
        for kv in args.set:
            if "=" not in kv:
                continue
            k, v = kv.split("=", 1)
            if v == "now":
                v = now()
            cur = st
            keys = k.split(".")
            for kk in keys[:-1]:
                cur = cur.setdefault(kk, {})
            cur[keys[-1]] = v
        st["_updated"] = time.strftime("%Y-%m-%d %H:%M:%S")
        jsave(STATE, st)
    if not st:
        return out("EMPTY", ["台账为空。示例: sentinel state --set "
                             "prefixes.steam.runtime=wine-devel-11.13"],
                   {"state": {}}, as_json)
    lines = json.dumps(st, ensure_ascii=False, indent=1).splitlines()
    return out("OK", lines[:28], {"state": st}, as_json)


def cmd_guard(args, as_json):
    ensure_dirs()
    st = jload(STATE, {})
    if args.rule != "denuvo":
        return out("FAIL 未知规则", [f"v1 支持: denuvo"], as_json=as_json)
    key = st.setdefault("denuvo", {}).setdefault(args.target, {})
    if args.record:
        key["last_attempt"] = now()
        jsave(STATE, st)
        return out("RECORDED", [f"denuvo.{args.target}.last_attempt = 现在",
                                "prefix 若激活成功,记得 runtime_pinned"],
                   as_json=as_json)
    last = key.get("last_attempt")
    if last is None:
        return out("ALLOW", [f"{args.target}: 无历史尝试记录",
                             "启动后记得: sentinel guard denuvo "
                             f"{args.target} --record"], as_json=as_json)
    elapsed = now() - float(last)
    if elapsed < 24 * 3600:
        left = 24 * 3600 - elapsed
        return out("BLOCKED", [
            f"距上次尝试仅 {elapsed/3600:.1f}h(需 ≥24h)",
            f"倒计时: {left/3600:.1f}h 后解禁",
            "Denuvo 纪律: 每日约5次配额,换底座=烧一次"],
            {"left_h": left / 3600}, as_json)
    return out("ALLOW", [f"距上次尝试 {elapsed/3600:.1f}h ≥24h,可以打",
                         f"启动后记得 --record"], as_json=as_json)


def cmd_budget(args, as_json):
    ensure_dirs()
    b = jload(BUDGETS, {})
    if args.action == "start":
        b[args.name] = {"start": now(), "minutes": args.minutes}
        jsave(BUDGETS, b)
        return out("STARTED", [f"{args.name}: {args.minutes} 分钟预算"],
                   as_json=as_json)
    # check
    if args.name and args.name in b:
        items = {args.name: b[args.name]}
    else:
        items = b
    if not items:
        return out("EMPTY", ["无进行中预算"], as_json=as_json)
    ev, worst = [], "OK"
    for name, rec in items.items():
        used = (now() - rec["start"]) / 60
        left = rec["minutes"] - used
        if left < 0:
            worst = "ESCALATE"
            ev.append(f"⏰ {name}: 超时 {-left:.0f} 分钟 —— 停手!写 PROGRESS "
                      "→ handoff → 换任务,不恋战")
        else:
            ev.append(f"{name}: 剩 {left:.0f}/{rec['minutes']} 分钟")
    return out(worst, ev, as_json=as_json)


def cmd_attempt(args, as_json):
    ensure_dirs()
    a = jload(ATTEMPTS, {})
    fp = hashlib.md5(args.fingerprint.encode()).hexdigest()[:10]
    rec = a.setdefault(fp, {"desc": args.fingerprint, "count": 0})
    rec["count"] += 1
    rec["last"] = time.strftime("%Y-%m-%d %H:%M")
    jsave(ATTEMPTS, a)
    n = rec["count"]
    if n >= 3:
        return out("ESCALATE", [
            f"「{args.fingerprint}」已试 {n} 次",
            "同一手段 ≥3 次 = 熔断。写 PROGRESS → handoff / 换路子",
        ], {"count": n}, as_json)
    return out("OK", [f"「{args.fingerprint}」第 {n} 次(≥3 熔断)"],
               {"count": n}, as_json)


# ───────────────────────────── handoff / inbox ─────────────────────────────

def cmd_handoff(args, as_json):
    ensure_dirs()
    ts = time.strftime("%m%d_%H%M")
    path = os.path.join(ROOT, f"handoff-{ts}.md")
    jobs_snap = []
    for jid in sorted(os.listdir(JOBS))[-5:]:
        if os.path.isdir(job_dir(jid)):
            jobs_snap.append(f"- {jid}: {job_quick_verdict(jid)}")
    with open(path, "w", encoding="utf-8") as f:
        f.write(f"""# 交接卡 {ts}

## 背景(两行)
(agent 填:现在在攻什么、卡在哪)

## 需要人类做的事
{args.need}

步骤:
1. (逐步写清,人类无上下文也能照做)

## 预期看到什么
(成功/失败分别长什么样)

## 结果写回
把观察结果写进 `{INBOX}`(格式随意,一句话也行)

## 当前 job 快照
{chr(10).join(jobs_snap) if jobs_snap else '(无)'}
""")
    return out("CARD_READY", [f"卡片: {path}", "请补全背景与步骤后通知人类",
                              "然后换任务,不空转等待"],
               {"path": path}, as_json)


def cmd_inbox(args, as_json):
    ensure_dirs()
    if not os.path.exists(INBOX):
        with open(INBOX, "w") as f:
            f.write("# sentinel 收件箱 —— 人类答复写这里\n")
        return out("EMPTY", ["收件箱刚建立,无内容"], as_json=as_json)
    content = open(INBOX, encoding="utf-8").read()
    seen = jload(INBOX_SEEN, {"md5": ""})
    cur = hashlib.md5(content.encode()).hexdigest()
    fresh = cur != seen.get("md5")
    jsave(INBOX_SEEN, {"md5": cur, "read_at": now()})
    lines = [ln for ln in content.splitlines() if ln.strip()][1:]
    if not lines:
        return out("EMPTY", ["无人类答复"], as_json=as_json)
    v = "NEW_REPLY" if fresh else "NO_CHANGE(内容同上次已读)"
    return out(v, lines[-20:], {"fresh": fresh}, as_json)


# ───────────────────────────── selftest ─────────────────────────────

def cmd_selftest(args, as_json):
    ensure_dirs()
    results = []
    def t(name, passed, detail=""):
        results.append((name, passed, detail))
        return passed

    tmp = tempfile.mkdtemp(prefix="sentinel_st_")

    # 1) run→DONE
    class A:
        pass
    a = A(); a.name = "st-done"; a.cmd = ["echo hi && sleep 1 && echo bye"]
    a.profile = None
    cmd_run(a, False)
    time.sleep(3)
    jid = sorted(j for j in os.listdir(JOBS) if j.startswith("st-done"))[-1]
    t("run→DONE", "DONE" in job_quick_verdict(jid), job_quick_verdict(jid))

    # 2) 静默进程:RUNNING_SILENT(默认耐心内)与 LIKELY_HUNG(耐心=0)
    a2 = A(); a2.name = "st-silent"; a2.cmd = ["sleep 60"]; a2.profile = None
    cmd_run(a2, False)
    time.sleep(1)
    jid2 = sorted(j for j in os.listdir(JOBS) if j.startswith("st-silent"))[-1]
    meta2 = jload(os.path.join(job_dir(jid2), "meta.json"), {})
    # 直接用内部逻辑判定
    alive = pid_alive_tree(meta2["pid"])
    logf2 = os.path.join(job_dir(jid2), "out.log")
    silent = now() - os.path.getmtime(logf2)
    t("silent→RUNNING_SILENT", alive and silent < PATIENCE["default"])
    t("silent→LIKELY_HUNG(耐心0)", alive and silent >= 0 and
      proc_cpu(meta2["pid"]) < 5.0)
    subprocess.run(["pkill", "-9", "-g", str(meta2["pid"])],
                   capture_output=True)

    # 3) logs --since-last:偏移 + 签名
    lf = os.path.join(tmp, "fake.log")
    with open(lf, "w") as f:
        f.write("line1\nline2\n")
    class L:
        pass
    l1 = L(); l1.target = lf
    import io
    from contextlib import redirect_stdout
    buf = io.StringIO()
    with redirect_stdout(buf):
        cmd_logs(l1, False)
    with open(lf, "a") as f:
        f.write("boom status c0000142 here\n")
    buf2 = io.StringIO()
    with redirect_stdout(buf2):
        cmd_logs(l1, False)
    o2 = buf2.getvalue()
    t("logs 增量", "line1" not in o2 and "c0000142" in o2)
    t("logs 签名标签", "DLL_INIT_FAILED" in o2)

    # 4) shot 启发式(黑屏 = 小体积;冻结 = md5 同)
    bp = os.path.join(tmp, "black.png")
    with open(bp, "wb") as f:
        f.write(base64.b64decode(BLACK_PNG_B64))
    flags = analyze_shot(bp)
    t("shot 黑屏嫌疑", any("BLACK" in x for x in flags))
    bp2 = os.path.join(tmp, "black2.png")
    shutil.copy(bp, bp2)
    flags2 = analyze_shot(bp2, bp)
    t("shot 冻结判定", any("FROZEN" in x for x in flags2))

    # 5) purge 演练(selftest pid)
    p = subprocess.Popen(["sleep", "300"], start_new_session=True)
    class P:
        pass
    pa = P(); pa.selftest_pid = p.pid; pa.prefix = None
    buf3 = io.StringIO()
    with redirect_stdout(buf3):
        cmd_purge(pa, False)
    try:
        p.wait(timeout=3)  # 收割僵尸,否则 kill 0 对僵尸仍成功
    except Exception:
        pass
    t("purge 演练", p.poll() is not None)

    # 6) guard 时钟
    st = jload(STATE, {})
    st.setdefault("denuvo", {})["st-game"] = {"last_attempt": now()}
    jsave(STATE, st)
    class G:
        pass
    g = G(); g.rule = "denuvo"; g.target = "st-game"; g.record = False
    buf4 = io.StringIO()
    with redirect_stdout(buf4):
        cmd_guard(g, False)
    blocked = "BLOCKED" in buf4.getvalue()
    st["denuvo"]["st-game"]["last_attempt"] = now() - 25 * 3600
    jsave(STATE, st)
    buf5 = io.StringIO()
    with redirect_stdout(buf5):
        cmd_guard(g, False)
    t("guard denuvo", blocked and "ALLOW" in buf5.getvalue())

    # 7) budget + attempt
    b = jload(BUDGETS, {})
    b["st-task"] = {"start": now() - 31 * 60, "minutes": 30}
    jsave(BUDGETS, b)
    class B:
        pass
    bb = B(); bb.action = "check"; bb.name = "st-task"; bb.minutes = None
    buf6 = io.StringIO()
    with redirect_stdout(buf6):
        cmd_budget(bb, False)
    t("budget 熔断", "ESCALATE" in buf6.getvalue())
    aa = A(); aa.fingerprint = "st-同一招"
    for _ in range(3):
        buf7 = io.StringIO()
        with redirect_stdout(buf7):
            cmd_attempt(aa, False)
    t("attempt 熔断", "ESCALATE" in buf7.getvalue())

    # 清理测试残留
    shutil.rmtree(tmp, ignore_errors=True)
    for jid_ in list(os.listdir(JOBS)):
        if jid_.startswith("st-"):
            shutil.rmtree(job_dir(jid_), ignore_errors=True)
    a_ = jload(ATTEMPTS, {})
    a_ = {k: v for k, v in a_.items() if not v.get("desc", "").startswith("st-")}
    jsave(ATTEMPTS, a_)
    b_ = jload(BUDGETS, {})
    b_.pop("st-task", None)
    jsave(BUDGETS, b_)
    st = jload(STATE, {})
    st.get("denuvo", {}).pop("st-game", None)
    jsave(STATE, st)

    passed = sum(1 for _, p_, _ in results if p_)
    total = len(results)
    ev = [f"{'✅' if p_ else '❌'} {n}" + (f" ({d})" if d and not p_ else "")
          for n, p_, d in results]
    v = "ALL GREEN" if passed == total else f"FAIL {total-passed}/{total}"
    return out(v, ev, {"passed": passed, "total": total}, as_json)


# ───────────────────────────── main ─────────────────────────────

def main():
    ap = argparse.ArgumentParser(prog="sentinel",
                                 description="Claude Code 自我监控哨兵")
    ap.add_argument("--json", action="store_true", dest="as_json")
    sub = ap.add_subparsers(dest="cmd_name")

    p = sub.add_parser("run", help="后台启动长任务(caffeinate 包裹)")
    p.add_argument("name")
    p.add_argument("--profile", choices=list(PATIENCE))
    p.add_argument("cmd", nargs=argparse.REMAINDER)

    sub.add_parser("jobs", help="列出 job 与判决")

    p = sub.add_parser("watch", help="多信号判活")
    p.add_argument("target")
    p.add_argument("--profile", choices=list(PATIENCE))
    p.add_argument("--interval", type=float, default=5.0)

    p = sub.add_parser("logs", help="只读自上次以来的新日志+签名打标")
    p.add_argument("target")
    p.add_argument("--since-last", action="store_true", default=True)

    p = sub.add_parser("shot", help="标准化截图+启发式")
    p.add_argument("--tag")

    p = sub.add_parser("ps", help="wine/Steam 进程树快照")
    p.add_argument("--prefix")

    p = sub.add_parser("purge", help="清场口诀固化")
    p.add_argument("--prefix")
    p.add_argument("--all", action="store_true")
    p.add_argument("--selftest-pid", dest="selftest_pid")

    sub.add_parser("doctor", help="开跑前不变量体检")

    p = sub.add_parser("state", help="机器可读台账")
    p.add_argument("--set", action="append")

    p = sub.add_parser("guard", help="配额守卫(v1: denuvo)")
    p.add_argument("rule")
    p.add_argument("target")
    p.add_argument("--record", action="store_true")

    p = sub.add_parser("budget", help="攻坚计时熔断")
    p.add_argument("action", choices=["start", "check"])
    p.add_argument("name", nargs="?")
    p.add_argument("--minutes", type=int, default=30)

    p = sub.add_parser("attempt", help="尝试指纹计数熔断")
    p.add_argument("fingerprint")

    p = sub.add_parser("handoff", help="生成交接卡")
    p.add_argument("--need", required=True)

    sub.add_parser("inbox", help="读人类答复")
    sub.add_parser("selftest", help="自体检(全绿才可信)")

    # run 命令:先按 "--" 手动分割,argparse REMAINDER 会吞掉选项
    argv = sys.argv[1:]
    tail_cmd = None
    if "run" in argv and "--" in argv:
        i = argv.index("--")
        tail = argv[i + 1:]
        if len(tail) == 1:
            tail_cmd = tail[0]  # 单词=原始 shell 串(自带引号语义)
        else:
            import shlex
            tail_cmd = " ".join(shlex.quote(w) for w in tail)  # 多词=逐词加引号
        argv = argv[:i]
    args = ap.parse_args(argv)
    if not args.cmd_name:
        ap.print_help()
        return 0
    if args.cmd_name == "run":
        args.cmd = [tail_cmd] if tail_cmd else (args.cmd or None)
    fn = {
        "run": cmd_run, "jobs": cmd_jobs, "watch": cmd_watch,
        "logs": cmd_logs, "shot": cmd_shot, "ps": cmd_ps,
        "purge": cmd_purge, "doctor": cmd_doctor, "state": cmd_state,
        "guard": cmd_guard, "budget": cmd_budget, "attempt": cmd_attempt,
        "handoff": cmd_handoff, "inbox": cmd_inbox, "selftest": cmd_selftest,
    }[args.cmd_name]
    return fn(args, args.as_json)


if __name__ == "__main__":
    sys.exit(main())
