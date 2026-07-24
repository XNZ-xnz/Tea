# Tea 项目交接文档（App 版 → Terminal 版 Claude Code）

> 写于 2026-07-24 下午。上一会话跨越两天两夜：macOS 26 降级重建 → CEF 黑屏根治 → Denuvo 定性 →
> 自建现代 DXVK 打通 → 三款游戏攻坚。本文是**完整状态转移**——新会话开工先读
> `CLAUDE.md`（工作守则）→ 本文（当前状态）→ `PROGRESS.md`（全部历史细节与实验矩阵）。
> 旧的降级交接见 `docs-archive-HANDOFF-downgrade.md`（已完成使命）。

## 〇、三十秒状态总览

| 战线 | 状态 | 下一步 |
|---|---|---|
| **Steam 客户端** | ✅ 完整可用（CEF 黑屏已根治，登录态 bombpee/XNZ 在） | 无 |
| **P5R**（1687950，Denuvo） | 图形栈验证可用；卡 Denuvo 激活配额 88500006，**冷却中** | 确认 >24h 零启动后用锁定组合一次通关（见 §3.1） |
| **幸福工厂**（526870，UE5.3） | 自建 DXVK 下渲染最深；`-nosound` 绕过音频崩点后撞交换链 887A0004 | §3.2 的组合矩阵还剩 2-3 发 |
| **Against the Storm**（1336490，Unity DX11） | 🏆 **已通关到可交互主菜单**（2026-07-24 15:30，截图+HUD+日志三重实证） | 只剩 5-6 FPS 帧率问题，见 PROGRESS「AoTS 里程碑」段 |
| **BioShock Infinite**（8870，32 位） | 判死封存：wow64 早期启动死角，与 DXVK 无关（wined3d baseline 同卡点） | 不投入；等 wow64 演进 |
| **自建 DXVK**（核心资产） | ✅ 上游 DXVK 3.0.2 + 5 处补丁，64/32 位都已编译，**已被 AoTS 实证可用** | 复用到一切 DX11 游戏 |

## 一、核心资产清单（都在哪、怎么用）

### 1.1 自建 DXVK（本项目最重要技术资产）
- **补丁**：`patches/dxvk-macos-m4/tea-dxvk-m4-moltenvk.patch` + `README.md`（构建全流程）。
  内容：4 个设备特性门 required→optional（geometryShader/shaderCullDistance/depthClipEnable/robustBufferAccess2+nullDescriptor）
  + d3d11_query.cpp GetData 对 MoltenVK Invalid/Failed 查询容错（continue 而非 INVALID_CALL）。
- **预编译产物**（可直接用）：`~/Library/Application Support/Tea/user-provided/dxvk-tea-build/{x64,x32}/`
  各含 d3d11.dll / dxgi.dll / d3d10core.dll。
- **源码树**（含增量构建目录，会话结束可能被清理，丢了按 README 重建 ~10 分钟）：
  `/private/tmp/claude-501/-Users-xnz-Desktop-Mac-Gaming-Porting/65ba87cc-*/scratchpad/dxvk-src/`
- **部署法（per-game 正解）**：DLL 拷进游戏 exe 同目录 + 启动环境 `WINEDLLOVERRIDES="d3d11,dxgi,d3d10core=n,b"`。
  ⚠️ 幸福工厂交换链一度需要**同时放 prefix system32**（"同源认亲"，见 PROGRESS 887A0004 段），
  但 system32 部署会污染同 prefix 所有游戏（尤其 P5R）——**用完必须还原**
  （备份在 `~/Library/Application Support/Tea/prefixes/dxmt-backup-sys32/`，当前已还原 ✅）。
- **工具链已全通**：Xcode license 已接受（产品负责人 7/24 上午执行），meson/ninja/glslang/mingw-w64 都在 brew。
  重建命令见 patches README。

### 1.2 steamwebhelper 包装器（CEF 黑屏根治）
- 已部署在 steam prefix 的 Steam/bin/cef/cef.win64/（原版改名 `steamwebhelper_real.exe`）。
- 源码：`tools/steamwebhelper-wrapper/`（MIT，源自 notpop/steam-on-m1-wine）。
- `Steam/Steam.cfg` 写了 `BootStrapperInhibitAll=enable` 防还原。若 Steam 强更后 UI 又黑，
  按 tools 里 README 的体积判别法重装包装器（Valve 原版 >6MB，包装器 <200KB）。

### 1.3 Runtimes（`tea runtime list` 全部识别）
- `wine-devel-11.13+winemetal`：Steam 客户端主力底座（CEF 安全）。
- `wine-devel-11.13+winemetal+mvk142`：**游戏主力底座**（同上 + MoltenVK 升级到 1.4.2，Vulkan 1.4，DXVK 需要它）。
- `winecx-xom-5.4.2`：能带 Steam UI；但跑 P5R 崩固定地址、跑 UE5 exe 孵化僵死——仅备用。
- `wine-3shain-9.9`：DXMT 作者的 wine（树内集成 DXMT）；对 UE5.3 启动器有兼容回归（VC 弹窗死循环）——等 DXMT 生态演进再用。
- `gptk-wine-3.0-2`：D3DMetal 3；webhelper 病（-silent 也弹窗但不阻塞游戏进程）；D3DMetal 对 UE5 有采样器堆/LUID 双断言——DX12 路线暂封。
- 其余 dxmt 变体见 `tea runtime list`，历史用途见 PROGRESS。

### 1.4 CDP 全自动装机（P4「一键安装」原型）
- 起 Steam 带 `-cef-enable-debugging` → `curl localhost:8080/json` 找 `SharedJSContext` →
  `cdp-eval.swift`（tools/diagnostics/）执行 `SteamClient.Installs.OpenInstallWizard([appid])`。
- **确认安装的两种流**：老游戏 `ContinueInstall()` 即可（P5R 时代验证）；新游戏要**遍历全部 CDP page
  找 Install 按钮 DOM 点击**（AoTS 实测，`ContinueInstall` 无效）。EULA 是独立 CEF page，
  按文本扫描找到后点 Accept（**必须先经产品负责人授权**——EULA 属用户决策，产品哲学是不绕过用户界面）。
- swift 脚本要用 CLT 跑：`DEVELOPER_DIR=/Library/Developer/CommandLineTools swift tools/diagnostics/cdp-eval.swift <ws-url> <js>`。

### 1.5 诊断与监控工具
- `tools/diagnostics/`：winlist/winid/activate/cdp-shot/cdp-eval/qr 工具（README 有组合拳）。
- 屏幕录制权限**已授予**终端——`screencapture -x -o -l <windowID>` 窗口级截屏随便用，
  纯黑 PNG 体积极小（~50-95KB@1280px），有内容 >300KB，可作自动判定指标。
- 监控纪律（产品负责人硬要求）：**每个实验挂三重指标监视**（游戏日志尺寸 + 截图字节 + 进程数），
  600 秒无变化必须报警转下一步；**每轮抓全部 wine 窗口**防漏小对话框（两次教训）。
- 杀 wine：`pkill -9 -f "wine-preloader|wine64-preloader"` 只对 gptk/CX 系底座有效。
  **wine-devel-11.13 系底座没有 preloader，这条口诀杀不掉任何游戏进程**（2026-07-24 实测踩坑，
  导致以为清场干净、实则游戏还活着，第二轮被 Steam 挡回 "Game already running"，环境变量全部没生效）。
  **通用清场序列**：`pkill -9 -f "<游戏exe名>"` → `pkill -9 -f "steam.exe|steamwebhelper"` →
  `pkill -9 -f "wineserver|winedevice"`，最后 `pgrep -fl "wine|steam"` 必须为空。
- **截屏陷阱**：`screencapture -l <windowID>` 抓被遮挡的 wine 窗口返回**陈旧缓存表面**，连抓多次字节数
  完全一致，极易误判成「渲染冻结」。判定呈现是否活着：先 activate 窗口到前台再连抓两张比字节数，
  或直接开 `DXVK_HUD=fps` 看数字。

## 二、当前部署状态（精确到文件）

- **steam prefix**（`~/Library/Application Support/Tea/prefixes/steam`，43GB，含登录态）：
  - system32/syswow64：已还原为 DXMT-era 原状（dxmt-backup-sys32 为备份源）✅
  - 注册表：P5R.exe 的 AppDefaults DllOverrides **已删除**；HasRunKey 已写（跳 32 位 redist）；
    VC 2015-2022 x64 已真实安装；VC 伪造键（VisualStudio\14.0\VC\Runtimes 各变体）残留无害；
    虚拟桌面注册表**已还原**（实验后清理）✅
  - 游戏目录内的 DXVK 部署（per-game，保留待用）：
    - `Satisfactory/FactoryGame/Binaries/Win64/`：自建 DXVK x64 三件套 ✅
    - `Against the Storm/`：自建 DXVK x64 d3d11+dxgi+d3d10core + `steam_appid.txt` ✅
    - `BioShock Infinite/Binaries/Win32/`：自建 DXVK x32 三件套（游戏已封存，DLL 无害）
  - GameOverlayRenderer64.dll/GameOverlayRenderer.dll 改名 `.disabled`（P5R 排查时禁的，
    对游戏无碍；若要恢复 overlay 改回原名）。
- **进程**：交接时全部 wine/Steam 进程已杀干净 ✅
- **Surge 代理**：三个订阅配置（Flower_SS/Nexitally_Surge/WgetCloud）的 `always-real-ip` 已加
  steam CDN 白名单（*.steamcontent.com/*.steamserver.net/*.pphimalayanrt.com/*.eccdnx.com/*.clngaa.com/*.steamstatic.com），
  **需产品负责人在 Surge 里 reload 配置才生效**。原配置备份在会话 scratchpad（surge-backup/），
  scratchpad 若被清，配置文件本身在 `~/Library/Mobile Documents/iCloud~com~nssurge~inc/Documents/`。
  这根治 Steam 下载被 Fake-IP(198.18.x) 掐死的问题；未 reload 前下载卡了就重启 Steam 续传（实测有效）。

## 三、三条战线的精确下一步

### 3.1 P5R（最近的胜利，但纪律优先）
- **状态**：图形栈验证可用（DXVK-macOS 1.10.3 repack 时代已实证 FL 11_0+交换链；现在游戏目录是它还是自建版
  需检查——`P5R/` 游戏目录里的 d3d11.dll 是 1.10.3 repack 的）。卡 Denuvo 88500006 纯限流。
- **纪律（血泪）**：每次启动尝试都可能烧一次激活、把 24h 窗口后推。**动手前先确认距上次启动 >24h**
  （上次启动 2026-07-24 中午 ~12:30）。杀进程绝不点 Denuvo 弹窗按钮。
- **通关序列**：Steam 用 `wine-devel-11.13+winemetal` 起（正常模式）→ 游戏经 Steam 客户端语境启动
  （直启带 SteamAppId=1687950 也实证能到 Denuvo 校验）→ env `WINEDLLOVERRIDES="d3d11,d3d10core=n,b"
  ROSETTA_ADVERTISE_AVX=1`（**AVX 必须**，cpuid 实测 flag 才点亮）→ 标题画面 = P3 端到端达成。
  **之后该 prefix 永不换底座**（Denuvo 指纹稳定）。
- 若长冷却后仍 88500006 → 转指纹稳定性调查（CrossOver 能跑证明 Denuvo 在 wine 可过）。

### 3.2 幸福工厂（UE5.3，深水区）
- 全部 13+ 实验矩阵在 PROGRESS.md。关键已知：
  - 自建 DXVK 让它走到最深（设备✓交换链✓查询补丁✓→ 音频初始化 CoreUObject null-deref）。
  - **`-nosound` 绕过音频崩点**（实证），但那次撞了交换链 887A0004（当时 DXVK 只在游戏目录没在 system32）。
- **待试组合（下一发）**：DXVK 双部署（游戏目录+system32，记得完事还原）+ `-nosound` + mvk142 底座
  + 直启（SteamAppId=526870）。若过了，逐步解锁音频（去掉 -nosound 换 wine 音频参数排查 null-deref 根源）。
- 音频崩溃上下文：崩前日志停在 audio submix/MasterReverbSubmix/audio stream 初始化（PROGRESS 有全文）。

### 3.3 Against the Storm ✅ 已通关到可交互主菜单（2026-07-24 15:30）
- 组合：`wine-devel-11.13+winemetal+mvk142` 底座 + 游戏目录自建 DXVK + `WINEDLLOVERRIDES="d3d11,dxgi,d3d10core=n,b"`，经 Steam `rungameid` 启动。
- 实证：Unity 2021.3.45f2 / `Direct3D 11.0 [level 11.0]` / `Renderer: Apple M4` / DXVK HUD `3.0.2 + MoltenVK 1.4.2`；
  CGEvent 模拟点击可关弹窗、主菜单 PLAY/OPTIONS/QUIT 完整渲染。
- **剩余问题：5-6 FPS**（主线程阻塞型，非 CPU 打满、非画质设置、非着色器编译）。详见 PROGRESS 里程碑段。
- ⚠️ **本段旧结论（「FL 11_1」「A* 寻路跑过」「游戏干净自退」）已作废**——那是读到了 Steam Cloud 恢复的
  2024 年 Windows 主机 Player.log。AoTS 的 Player.log **会被 Steam Cloud 同步覆盖**，读日志前必须先验产物归属
  （mtime / md5 / 日志内 GPU 与系统字段）。
- Player.log 路径：`prefix/drive_c/users/xnz/AppData/LocalLow/Eremite Games/Against the Storm/Player.log`。

### 3.4 BioShock Infinite（封存）
32 位 wow64 早期启动死角（wined3d baseline 同卡点证明与 DXVK 无关）。不投入。教训：**验证用游戏选
64 位 + 无 DRM 花活的**（AoTS 就是按此标准换的）。

## 四、环境事实速查

- MacBook Air M4 / 16GB / **macOS 26.5.2 (25F84)** / Xcode 26.6（license 已接受）/ Rosetta 2 已装。
- 磁盘：交接时约 33GB 可用（P5R 39GB + 幸福工厂 28GB + AoTS 6.5GB + BioShock 16GB 都装着；
  空间紧张可先卸 BioShock——已封存）。
- gh 已登录 XNZ-xnz；git 推送用 `/opt/homebrew/bin/git`（避开偶发的 Xcode git 提示）。
- brew 已装：xcodegen gh mingw-w64 meson ninja glslang（+git）。
- `swift build` 绿；`swift test` 未跑过完整版 Xcode 下的（应该能过，16 测试）。
- Steam 账号 bombpee（XNZ），登录态在 prefix 里，扫码登录流程如需重来见 PROGRESS 第三夜战记。
- 产品负责人已拍板的方向（必须遵守）：①不绕过游戏菜单/EULA——用户必须能点真界面，直接加载地图仅诊断
  ②目标=某类型游戏 90% 能进界面 ③打法=底座工程+精选清单（DX11 世代先行）+配方长尾 ④Denuvo 游戏底座钉死。

## 五、给新会话的操作提醒

- 每完成一段更新 PROGRESS.md，git 小步提交推送（中文说人话）。
- 实验要挂三重指标监视 + 全窗口抓屏；10 分钟无变化必须换弹药，不空转。
- CrashReportClient.exe 弹窗/winedbg 弹窗是崩溃余波，pkill 清掉即可；直接裸 wine 调用时记得
  `WINEDLLOVERRIDES` 里加 `winedbg.exe=d`（tea run 会自动加）。
- 长任务（下载/编译）后台跑 + watchdog，别阻塞。
- Steam 下载停滞（0 bps + ContentServerDirectoryService failed）→ 重启 Steam 换 CM 连接即愈；
  Surge reload 后应根治。
- scratchpad 是会话级易失目录：本会话两个 scratchpad 里除已转移的 DXVK 产物外还有全程截图、
  监控脚本模板（watchdog.sh/capture_all.sh/winids.swift）——都是可再生的，丢了无妨。
