# Tea — Claude 工作守则（每次会话开始先读完本文件）

Tea 是免费开源的 macOS 原生应用（SwiftUI）：把 Windows 版 Steam 装进应用全自动管理的 Wine 环境，让 Mac 用户对无原生 Mac 版的 Steam 游戏一键安装、一键启动。定位 =「开源版 CrossOver 游戏模式 + Proton 式开箱即玩」。完整需求见仓库外的 `../claude-code-app-prompt.md`（产品负责人的原始指令）；当前进度与已定决策见 `PROGRESS.md`。

## 红线（不可逾越，每次会话自查）

1. **不打包、不分发** Apple / Valve / 游戏厂商的任何二进制。措辞定案（2026-07-25）：「Apple 专有组件（D3DMetal）仅经 Apple 认可的渠道获取：你自行从 Apple 下载的 GPTK，或 Apple 官方文档指向的预构建评估环境。Tea 自身的 Release 永不包含、永不镜像它们。」凡内含 D3DMetal 的 runtime（现 gptk-wine，将来 tea-base 覆盖态），首次获取前必须经用户一次性确认（CLI 提示/GUI 弹窗，说明组件来源与性质）。「导入 GPTK 解锁 DX12」作废——现状：DX12 由 gptk-wine（Apple 文档点名的预构建环境）提供；导入 GPTK 4 = 为 Tea Base 就绪后解锁最新一代 D3DMetal。Steam 安装器只在运行时从 Valve 官方地址获取。
2. **永不接触 Steam 凭据**：不读取、不存储、不记录、不自动填充；登录只发生在 Steam 自己的窗口里；不做任何绕过登录的自动化。
3. **下载与执行链是安全敏感区**：manifest 钉版本 + SHA256、仅 HTTPS、校验失败即停、不执行任何来源不明的东西。这部分代码测试先行，改动加倍谨慎。
4. 不虚构任何兼容性数据或测试结果；每份兼容报告必须有出处，找不到出处保持 Unknown。
5. 无遥测、无统计上报；诊断数据只在用户主动生成、亲眼过目后由用户自己提交。
6. 项目名、包名、域名不含 Steam / Proton / Deck / Whisky / CrossOver；界面提及仅作兼容性事实描述。
7. 许可证 GPL-3.0。可依许可借鉴 Whisky/Mythic 代码并保留署名；许可证不兼容的仓库只读参考、不复制代码。

## 架构（定死）

三层，严格单向依赖，Xcode 工程由 XcodeGen 从 `project.yml` 生成（**禁止手改 .xcodeproj**）：

- **Core**（`Sources/TeaCore`，Swift Package）：全部业务逻辑，配单元测试，`swift build` / `swift test` 独立可跑。
- **CLI**（`Sources/TeaCLI` → 可执行 `tea`）：Core 每个能力一个子命令（env/runtime/prefix/backend/steam/run/report）。这是自测武器：不需要用户账号的一切都用 CLI 真实闭环验证。
- **App**（`App/Sources`，SwiftUI）：只调用 Core，不含业务逻辑。

常用命令：`swift build && swift test`（Core+CLI）；`xcodegen && xcodebuild -project Tea.xcodeproj -scheme Tea build`（App）；CLI 二进制在 `.build/debug/tea`。

## 关键机制速查

- 磁盘布局：`~/Library/Application Support/Tea/{runtimes,prefixes,user-provided,logs,downloads}`，路径一律走 `TeaPaths`。
- runtime 规则：`manifest.json` 钉版本+SHA256；仅 HTTPS；校验失败即中止；装好的 runtime 目录只读不可变；升级=并排装新版本可回退。
- prefix 快照：APFS clonefile（`cp -c`）零成本快照/回滚。
- **★选后端方法论（2026-07-24 定型，两层）★**
  ①**抄作业优先（覆盖规则）**：碰任何游戏前，先查社区在 CrossOver 上怎么跑它
  （AppleGamingWiki / CodeWeavers 兼容库 / macgamingdb.app / Reddit macgaming），
  有已验证配置就原样复现（后端/启动项/ESync/画质），复现成功后才做自己的实验。
  实例：P5R 社区实测 DXVK+ESync 最佳、D3DMetal 过场严重卡顿——功课直接改变了第一发选择。
  ②**无作业可抄时的默认值：D3DMetal 优先**（见下）。
- **★图形后端铁律（2026-07-24 幸福工厂黑屏战定型）：一切游戏优先 D3DMetal★**
  （backend=d3dmetal + gptk-wine-3.0-2 + 官方环境变量，DX11 游戏加 `-dx11`——CrossOver 同款路线）。
  穷尽 d3dmetal 的选择（启动项/环境变量/直启 Shipping exe 绕启动器）后才退 DXVK/DXMT 等开源路径。
  理由：MoltenVK 对 DXVK 3.x 采样器堆动态索引有 codegen bug（tonemap 全黑，SPIR-V 级实锤，
  纯开源侧 4 种工作区全部无效）；D3DMetal 完全绕开 MoltenVK。开源 DXVK 栈仅作简单 DX11 游戏补充
  （风暴之城实证 55-60 FPS 可玩）。Steam 客户端本身仍用 wine-devel-11.13+winemetal（gptk-wine 会拖垮 webhelper）。
- **★主线（2026-07-25 方向修订 v2）：Tea Base——自建同代自由底座★**
  一周实测定性：**不缺翻译层，缺"与 D3DMetal 同代的底座"**（D3DMetal 3 已实证、自建 DXVK 已实证、
  GPTK 4 导入器就绪，卡住一切的是 CX22 代老 wine）。路线 A = 从 CodeWeavers LGPL 公开源码
  （crossover-sources 25/26）Rosetta 自建 `tea-base-cx25/26`（GPTK 1 官方安装方式就是 brew 编
  crossover-sources，自建是正统玩法）。四步走 A1 侦察→A2 构建→A3 覆盖验证（先 D3DMetal 3 隔离
  OS 变量，后 D3DMetal 4）→A4 游戏验证（幸福工厂帧率对比/KCD2 主菜单/Steam 单底座重测）。
  撞硬墙转路线 B（按 A1 缺口清单把胶水 ABI 移植进 vanilla wine-devel）；B 亦不通接受双模式现状。
  **无论成败，Tea Base 有结论后 P4（GUI）即启动，不再漂移。**构建资产入 `tools/teabase/`。
- **图形后端矩阵（2026-07-25 定案）**：D3DMetal 3（✅ 可用，DX12/UE 硬骨头主力）｜D3DMetal 4
  （登记待用，Tea Base 打通后的最新主力）｜自建 DXVK 3.0.2（✅ AtS 55-60fps 实证，DX11/Unity
  主力，独家资产）｜DXMT（等符号导出底座）｜已知天花板（文档化不再投入）：MoltenVK codegen bug
  （待报上游）、32 位 wow64 早期启动死角（BioShock 封存）。
- Wine 来源（2026-07-23 实测）：现役主力 = Gcenx **game-porting-toolkit**（gptk-wine 原装含 D3DMetal 3）；
  开源补充 = Gcenx **macOS_Wine_builds**（WineHQ 官方构建）+ 自建 DXVK/DXMT 变体。
  GPTK 4 库需 CX24/25 代底座（实测 c0000142）→ 这正是 Tea Base 要补的缺口。
- Steam：默认单一 `steam` prefix；库解析读 `libraryfolders.vdf` + `appmanifest_*.acf`（自写解析器，fixture 单测）；启动链 = `steam.exe -silent` 后经 `steam://rungameid/<appid>`。
- recipes：`recipes/<appid>.yaml` 声明 wine 版本/后端/环境变量/DLL overrides/启动参数；无 recipe 走默认策略（读 exe 导入表猜 DX 版本）。
- 兼容徽章四档 Verified/Playable/Unsupported/Unknown × 硬件三档 base/pro/max；数据在 `compat/`，规则见原始指令第 6 节。

## 实战纪律（2026-07-25 入宪，全部来自实测踩坑）

1. **游戏日志新鲜度三查**：读任何游戏产物日志前先验 ①mtime 在本次运行区间 ②md5 对比运行前后
   ③日志内环境字段（GPU 名/路径/分辨率）与本机自洽。Steam Cloud 会把用户其他机器的
   Player.log/存档同步下来（AoTS 2024 旧日志、P5R 2023 Windows 存档两次实锤）。
2. **底座切换清场口诀**：换 wine 前对**所有** runtime 执行 `wineserver -k` + `pkill -9 -f wine`。
   残留 wineserver 版本冲突（"version mismatch 956/755"）表现为静默秒退，已多次误导判断。
   注意 wine-devel 无 preloader，`pkill -f wine-preloader` 打不中——用 `pkill -9 -f "<exe名>"`。
3. **窗口焦点与截图判活**：窗口级 `screencapture -l` 可能取到陈旧 surface；判活用全屏截图两次
   md5 对比（变=在渲染）。frontmost 用 `osascript` 按 unix id 设置。自动键鼠注入进不去
   捕获鼠标的第一人称游戏——可玩性最终确认交给产品负责人真人上手。
4. **Denuvo 纪律**：每日约 5 次激活配额，每换底座=新指纹=烧一次。动手前确认距上次任何启动
   >24h；杀进程绝不点 Denuvo 弹窗按钮；激活成功后 prefix 永久钉死底座（`runtime_pinned`）。
   激活后 token 缓存，同底座重启不烧配额。
5. **shader 编译等待**：D3DMetal 冷启动 shader 编译可长达 20 分钟（007 First Light 卡 99% 属
   正常）——「卡 99% ≠ 死机，勿杀进程」。游戏突然不启动可清 shader cache：
   `$(getconf DARWIN_USER_CACHE_DIR)/d3dm/<GAME>/shaders.cache`。
6. **性能诊断前先查系统负载**：accountsd/distnoted 泄漏、swap 爆满会把 55 FPS 压到 5 FPS。
   帧率异常先 `top` 看系统态，别急着怪翻译层（AoTS 实锤：重启后 4.8→55 FPS）。

## 工作方式

- 默认自主推进：构建绿+测试绿就继续，按 P0→P6 顺序（原始指令第 10 节）。重要决策记进 `PROGRESS.md`。
- 必须停下叫产品负责人的四种情况：GUI 界面可用时（看设计）；需要登录 Steam/启动已购游戏的端到端验证；签名/公证/发布；触碰红线或重大偏离。
- 同一错误卡 30 分钟：现象与已试方案写进 `PROGRESS.md`，绕开做别的，问题攒着一次问。
- 版本号、下载地址、dmg 结构等一切事实以官方仓库/官方文档/实物为准，不信训练记忆。
- git 小步提交，提交信息说人话（中文）。每阶段完成更新 `PROGRESS.md`。
- 界面与文案：简约克制、深色优先、原生 macOS 质感；中文文案禁止"不是X而是Y"、"综上所述"、零信息形容词；观点用事实演出来。
- 用户环境：MacBook Air M4 / 16GB / macOS 27 beta / Xcode 27 beta / GPTK 4 dmg 在 `/Users/xnz/Desktop/Mac Gaming Porting/Game_Porting_Toolkit_4.0_beta_1.dmg`。App 部署目标 macOS 26（若实测 D3DMetal 4 硬性要求 27 再上调并记录）。
- 仓库固定在 `~/Projects/Tea`。**严禁把仓库或构建目录放进桌面/文稿等 iCloud 同步路径**——FileProvider/FinderInfo xattr 会让 codesign 报 "resource fork, Finder information, or similar detritus not allowed"（2026-07-23 实测踩坑后搬家），构建垃圾还会上传 iCloud。
