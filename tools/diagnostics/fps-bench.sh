#!/bin/zsh
# 游戏帧率基准采样（8 次，取中位）
# 用法: fps-bench.sh <游戏exe名> <标签> [输出目录]
#   例: fps-bench.sh "Against the Storm.exe" ctrl /tmp/bench
#
# 前置：游戏已在跑，且启动时带了 DXVK_HUD=fps,gpuload,drawcalls
#
# 五条测量纪律（2026-07-24 逐条踩坑得出，违反任何一条数据即作废）：
#  1. Unity 窗口失焦即暂停整个循环 —— 非前台状态下测的帧率全是垃圾。
#     判据：游戏进程 CPU 掉到个位数 % 就是暂停了。
#  2. `screencapture -l <windowID>` 对 wine 窗口返回**陈旧缓存表面**，
#     连抓多次字节数完全一致会被误判成「渲染冻结」。只能用全屏 `screencapture -x -o`。
#  3. 拿焦点只有一个可靠办法：`osascript` 按 unix id 设 frontmost。
#     NSRunningApplication.activate（activate.swift/AppKit）对 wine 窗口不生效，
#     而且 AppKit 脚本进程自身会抢焦点，在采样循环里调用等于每次都破坏焦点。
#     模拟点击也不可靠：落点稍有偏差就打在 Steam 窗口(约 x120-1379/y58-869) 或 Dock(底部约90点)上。
#  4. `pgrep -f "<exe名>"` 会误匹配 UnityCrashHandler64.exe 和发起命令的 shell，
#     取 pid 前必须过滤。
#  5. 游戏进程 CPU% 不可当活性判据：GPU 打满时 CPU 本就空闲，且 wine/Rosetta 下 ps time 低报。
#     唯一可靠判据是**全屏截图字节数是否变化**。
set -u
EXE="${1:?用法: fps-bench.sh <游戏exe名> <标签> [输出目录]}"
TAG="${2:?缺少标签}"
OUT="${3:-${TMPDIR:-/tmp}/tea-fps-bench}"
mkdir -p "$OUT"
HERE="$(cd "$(dirname "$0")" && pwd)"
SW="DEVELOPER_DIR=/Library/Developer/CommandLineTools swift"

GPID=$(pgrep -fl "$EXE" | grep -v UnityCrashHandler | grep -v zsh | head -1 | cut -d' ' -f1)
[ -z "$GPID" ] && { echo "游戏没在跑：$EXE"; exit 1; }
echo "游戏 pid=$GPID"

focus() { osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $GPID) to true" >/dev/null 2>&1; }

focus
sleep 4
rm -f "$OUT/${TAG}"[0-9].png
for i in 1 2 3 4 5 6 7 8; do
  focus                      # 每次采样前重设前台：osascript 不抢焦点，重复调用安全
  sleep 1
  screencapture -x -o "$OUT/${TAG}$i.png"
  sleep 5
done

VARIANTS=$(ls -la "$OUT/${TAG}"[0-9].png | awk '{print $5}' | sort -u | wc -l | tr -d ' ')
echo "不同字节数图片种类: $VARIANTS / 8   (1 = 画面冻结或游戏暂停，数据作废)"
eval $SW "$HERE/hudstrip.swift" "$OUT/strip-${TAG}.png" "$OUT/${TAG}"{1,2,3,4,5,6,7,8}.png
