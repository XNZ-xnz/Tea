# Tea 项目交接文档 —— 旧 Mac → 新 Mac 迁移版

> 写于 2026-07-25 深夜。本文是**完整状态转移 + 新机器搭建手册**。
> 新会话开工顺序:`CLAUDE.md`(工作守则+哨兵条款)→ 本文 → `PROGRESS.md`(全部历史)
> → `sentinel state` + `sentinel inbox`(机器台账)。
> 旧交接:`docs-archive-HANDOFF-app-to-terminal.md`(已完成使命)。

---

## 0. 三十秒总览(2026-07-25 深夜快照)

| 战线 | 状态 |
|---|---|
| Against the Storm | ✅ 完整可玩 55-60 FPS(自建 DXVK,compat 已录 Verified) |
| 幸福工厂 | ✅ 端到端可玩(D3DMetal 3 + `-dx11`,根启动器 FactoryGameSteam.exe);帧率课题待 tea-base |
| **D3DMetal 4** | 🏆 **冒烟级解锁**:`gptk-wine-3.0-2+fw4`(CX22 胶水+framework 4.0b1)D3D11+D3D12 全绿;UE5 断言 `bFoundMatchingDevice` 未过(outputs/LUID 已排除) |
| **Tea Base(主线)** | cx26 建成(两代胶水均 ABI 崩,relay 实证);**cx25 编译成功(MAKE_RC=0 零错误)——组装+冒烟是迁移后第一件事** |
| P5R | 激活疑似成功但 10s 静默退 = CrossOver 专有补丁缺口(AppleGamingWiki 实锤纯 wine 不 boot)→ tea-base 验证游戏;**Denuvo 时钟在 sentinel 台账** |
| BioShock | 封存(32 位 wow64 + MoltenVK tonemap 双天花板;129FPS 运行但黑帧,证据链完整入 recipe 8870) |
| 哨兵 sentinel | ✅ 建成入宪(selftest 11/11,真实 wine 全链路验收),`tools/sentinel/` |
| KCD2 | 未下载(磁盘 18GB 放不下 ~90GB;compat 已按内存/磁盘证据标注 base=Unsupported) |
| MoltenVK 上游 | issue 英文草稿备好(`patches/dxvk-macos-m4/moltenvk-issue-draft.md`)**待产品负责人过目后提交** |

## 1. 迁移资产清单

### 必须搬运(不可再生或含状态)
| 资产 | 位置 | 说明 |
|---|---|---|
| **Tea 仓库** | `~/Projects/Tea` | 已全部推 GitHub(`XNZ-xnz/Tea` main),新机 clone 即可 |
| **Claude 记忆** | `~/.claude/projects/-Users-xnz-Desktop-Mac-Gaming-Porting/memory/` | **项目路径绑定**!新机工作目录若同为 `~/Desktop/Mac Gaming Porting`,整目录拷入同路径;路径不同则拷到新路径对应的 projects 目录名下 |
| **GPTK 4 dmg** | `~/Desktop/Mac Gaming Porting/Game_Porting_Toolkit_4.0_beta_1.dmg`(100MB) | Apple 开发者账号可重下,直接拷省事 |
| **sentinel 台账** | `~/Library/Application Support/Tea/sentinel/`(state.json/inbox.md/attempts) | 小文件;拷 = 新机开局即有全部机器记忆(含 Denuvo 时钟) |
| **crossover-sources 两包** | `~/Library/Application Support/Tea/downloads/`(327MB) | 可重下(tools/teabase/README 有 URL+SHA256),拷省时 |

### 建议搬运(可再生但成本高)
| 资产 | 大小 | 再生成本 |
|---|---|---|
| `~/Library/Application Support/Tea/runtimes/`(14 个 runtime 含 fw4 混合/tea-base-cx26) | 13GB | Gcenx release 重下 + 全部覆盖操作重做(PROGRESS 有记录),1-2 小时 |
| `~/Library/Application Support/Tea/prefixes/`(Steam 登录态+4 游戏) | 98GB | Steam 重登 + 游戏重下(90GB+);**⚠️ P5R Denuvo 见 §4** |
| `~/Library/Application Support/Tea/user-provided/`(自建 DXVK 64+32 位产物) | 小 | 从 dxvk-src 重编 ~10 分钟 |

### 可丢弃(纯可再生)
- `~/Projects/tea-base-build/`(4.4GB):源码从 downloads 重展开;构建按 `tools/teabase/README.md`(~25 分钟/代;**cx25 的 build 产物若搬走可跳过重编,直接组装**)
- `~/Projects/Tea/reference/dxvk-src`+`reference/MoltenVK`(gitignore):重 clone;
  **tea/moltenvk-m4 本地分支内容已完整同步进 `patches/dxvk-macos-m4/*.patch`**——
  重放 = dxvk upstream `1a5919b7` + dxbc-spirv `c5c1a5b` + apply 两个 patch

### 迁移方式建议
**迁移助理(Migration Assistant)整机迁移最省心**——上表全部自动到位,系统权限大多保留,
新机只需验证 §2 第 7 步 + 权限。手动迁移则按上表拷贝 + §2 全步骤。

## 2. 新 Mac 依赖安装清单(按序执行)

```bash
# 1. Rosetta 2(一切 x86_64 wine 的前提)
softwareupdate --install-rosetta --agree-to-license

# 2. Xcode(App Store 完整版;swift 诊断工具+Metal 工具链)+ CLT
xcode-select --install

# 3. Homebrew(arm64 原生)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 4. 构建工具链(Tea Base 与 DXVK 自编都要)
brew install mingw-w64 meson ninja bison xcodegen gh
# bison 必须 brew 3.8(系统 2.3 太老);构建时 PATH 前置 /opt/homebrew/opt/bison/bin

# 5. gh 登录
gh auth login

# 6. 克隆仓库(⚠️ 严禁 Desktop/Documents 等 iCloud 路径——codesign detritus 实测坑)
mkdir -p ~/Projects && cd ~/Projects && gh repo clone XNZ-xnz/Tea

# 7. 验证核心链路
cd ~/Projects/Tea && swift build && swift test    # Core+CLI,16 测试全绿
python3 tools/sentinel/sentinel.py selftest        # 哨兵 11/11 全绿
python3 tools/sentinel/sentinel.py doctor          # 开跑体检(会暴露缺权限/缺 Rosetta)
```

### Claude Code 侧
```
/plugin marketplace add apple/game-porting-toolkit
/plugin install game-porting-skills@game-porting-toolkit
```
- 已实测价值:Metal 验证层(`MTL_DEBUG_LAYER`/`MTL_SHADER_VALIDATION`)诊断 64 位游戏;
  黑屏诊断症状路由表;方法论对闭源游戏不适用(需源码),完整评估见 PROGRESS。
- 模型:Fable 5(用户默认)。工作目录:`~/Desktop/Mac Gaming Porting`(dmg+文档;仓库在 ~/Projects/Tea)。

### 系统权限(一次性,授给跑 Claude 的终端 App)
1. **屏幕录制**(sentinel shot):系统设置 → 隐私与安全性 → 屏幕录制
2. **辅助功能**(type.swift/click.swift 键鼠注入):同上 → 辅助功能
3. 验证:`sentinel doctor` 全绿即可开工

### wine runtime 来源(若不搬 runtimes 目录)
- Gcenx GPTK cask:`github.com/Gcenx/game-porting-toolkit` releases(3.0-2/3.0-3,CX22 代)
- Gcenx wine:`github.com/Gcenx/macOS_Wine_builds`(wine-devel-11.13)
- MoltenVK 1.4.2 dylib(wine-devel 用 + 过 CX 构建链检)
- 覆盖操作(DXVK 游戏目录部署/fw4 混合/rpath/符号链接)全记录在 PROGRESS + tools/teabase/README

## 3. 迁移后第一件事(A3 断点续接)

**cx25(Wine 10)已编译成功,差组装+冒烟**——D3DMetal 4 全套(同代胶水+框架)成立与否的判定:

1. `sentinel state` + `sentinel inbox`(读台账)
2. 按 `tools/teabase/README.md` 组装手册:make install DESTDIR → runtime 组装 →
   rpath 两处(ntdll.so + bin/wine)→ GPTK4 全套胶水 + external + nvngx 重命名 + 符号链接
3. `sentinel purge` + `sentinel doctor` 双绿 → 冒烟 d3d11+d3d12
   (`tools/d3d11-smoke/`,编译带 `-ldxguid`;WINEDLLOVERRIDES 加 `mscoree,mshtml=d` 防 prefix 挂)
4. **通** → 幸福工厂上 tea-base-cx25+d3dm4(A4 帧率对比 vs gptk-wine 基线);P5R 复验
   (guard 必查);Steam 单底座重测 → 双模式坍缩判定
5. **不通** → 深挖 UE5 `bFoundMatchingDevice`(已排除:outputs 枚举/LUID 匹配/MTL_HUD/
   `-graphicsadapter=0`;嫌疑:WineRegistry 喂的驱动版本信息);fw4 混合可先服务非 UE 游戏

## 4. 关键警告(迁移特有)

1. **⚠️ P5R Denuvo 激活是硬件指纹绑定**——新 Mac = 新指纹 = 首启动烧一次新激活(每日约 5 次)。
   prefixes 整体搬运**不能**免除重激活。新机首 launch 前 `sentinel guard denuvo 1687950` 必查,
   启动后 `--record`;激活成功即钉死底座(`runtime_pinned`)。
2. **仓库/构建目录严禁 iCloud 路径**(Desktop/Documents)——FileProvider xattr 让 codesign 报
   detritus(旧机实测)。`~/Projects/` 是安全区。
3. **runtime 只读不可变**:变体一律 APFS 克隆(`cp -c -R`)并排建,勿改原目录。
4. 旧机 macOS 26.5.2。**新机若是 macOS 27**:同 GPTK 在 27 更快(Andrew Tsai 数据),且解锁
   `D3DM_MTL4=1`(Metal 4 后端)与 gpucapture CLI——A3 通过后值得直接测,并把结果记 PROGRESS。
5. Steam 登录是「真人工介入」:prefix 重建时需你亲手登录一次(CEF 包装器在
   `tools/steamwebhelper-wrapper/`,Steam.cfg `BootStrapperInhibitAll=enable` 防还原)。
6. 换机后哨兵台账里的 `os` 字段记得更新:`sentinel state --set os=<新版本>`。

## 5. 各文档去哪读什么

| 要什么 | 读哪里 |
|---|---|
| 工作守则/红线/后端矩阵/哨兵八条款/实战纪律六条 | `CLAUDE.md` |
| 全部历史+实验矩阵+方向修订 v2 依据 | `PROGRESS.md` |
| 单游戏配方与攻坚史 | `recipes/<appid>.yaml` |
| 兼容数据(6 游戏+2 first-party 报告) | `compat/games/` + `compat/reports/` |
| Tea Base 构建/组装/踩坑(6 条)/已验证事实 | `tools/teabase/README.md` |
| 哨兵用法与设计原则 | `tools/sentinel/README.md` + CLAUDE.md 八条款 |
| DXVK 8 补丁 + MoltenVK issue 草稿 + 证据图 | `patches/dxvk-macos-m4/` |
| 机器台账(prefix 底座/Denuvo 时钟/战线状态) | `sentinel state` |

## 6. 新会话开工咒语

```
继续 Tea 项目。先读 CLAUDE.md、HANDOFF.md、PROGRESS.md,然后 sentinel state + sentinel inbox,
从「迁移后第一件事」(HANDOFF §3,cx25 组装+冒烟)开始。
```
