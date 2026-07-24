# Tea — Claude 工作守则（每次会话开始先读完本文件）

Tea 是免费开源的 macOS 原生应用（SwiftUI）：把 Windows 版 Steam 装进应用全自动管理的 Wine 环境，让 Mac 用户对无原生 Mac 版的 Steam 游戏一键安装、一键启动。定位 =「开源版 CrossOver 游戏模式 + Proton 式开箱即玩」。完整需求见仓库外的 `../claude-code-app-prompt.md`（产品负责人的原始指令）；当前进度与已定决策见 `PROGRESS.md`。

## 红线（不可逾越，每次会话自查）

1. **不打包、不分发** Apple / Valve / 游戏厂商的任何二进制。GPTK/D3DMetal 只走用户导入；Steam 安装器只在运行时从 Valve 官方地址获取。
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
- **★图形后端铁律（2026-07-24 幸福工厂黑屏战定型）：一切游戏优先 D3DMetal★**
  （backend=d3dmetal + gptk-wine-3.0-2 + 官方环境变量，DX11 游戏加 `-dx11`——CrossOver 同款路线）。
  穷尽 d3dmetal 的选择（启动项/环境变量/直启 Shipping exe 绕启动器）后才退 DXVK/DXMT 等开源路径。
  理由：MoltenVK 对 DXVK 3.x 采样器堆动态索引有 codegen bug（tonemap 全黑，SPIR-V 级实锤，
  纯开源侧 4 种工作区全部无效）；D3DMetal 完全绕开 MoltenVK。开源 DXVK 栈仅作简单 DX11 游戏补充
  （风暴之城实证 55-60 FPS 可玩）。Steam 客户端本身仍用 wine-devel-11.13+winemetal（gptk-wine 会拖垮 webhelper）。
- Wine 来源（2026-07-23 实测）：主力 = Gcenx **game-porting-toolkit**（gptk-wine 原装含 D3DMetal 3）；
  开源补充 = Gcenx **macOS_Wine_builds**（WineHQ 官方构建）+ 自建 DXVK/DXMT 变体。
  GPTK 4 库需 CX24/25 代底座（实测 c0000142），只导入登记暂不启用。
- Steam：默认单一 `steam` prefix；库解析读 `libraryfolders.vdf` + `appmanifest_*.acf`（自写解析器，fixture 单测）；启动链 = `steam.exe -silent` 后经 `steam://rungameid/<appid>`。
- recipes：`recipes/<appid>.yaml` 声明 wine 版本/后端/环境变量/DLL overrides/启动参数；无 recipe 走默认策略（读 exe 导入表猜 DX 版本）。
- 兼容徽章四档 Verified/Playable/Unsupported/Unknown × 硬件三档 base/pro/max；数据在 `compat/`，规则见原始指令第 6 节。

## 工作方式

- 默认自主推进：构建绿+测试绿就继续，按 P0→P6 顺序（原始指令第 10 节）。重要决策记进 `PROGRESS.md`。
- 必须停下叫产品负责人的四种情况：GUI 界面可用时（看设计）；需要登录 Steam/启动已购游戏的端到端验证；签名/公证/发布；触碰红线或重大偏离。
- 同一错误卡 30 分钟：现象与已试方案写进 `PROGRESS.md`，绕开做别的，问题攒着一次问。
- 版本号、下载地址、dmg 结构等一切事实以官方仓库/官方文档/实物为准，不信训练记忆。
- git 小步提交，提交信息说人话（中文）。每阶段完成更新 `PROGRESS.md`。
- 界面与文案：简约克制、深色优先、原生 macOS 质感；中文文案禁止"不是X而是Y"、"综上所述"、零信息形容词；观点用事实演出来。
- 用户环境：MacBook Air M4 / 16GB / macOS 27 beta / Xcode 27 beta / GPTK 4 dmg 在 `/Users/xnz/Desktop/Mac Gaming Porting/Game_Porting_Toolkit_4.0_beta_1.dmg`。App 部署目标 macOS 26（若实测 D3DMetal 4 硬性要求 27 再上调并记录）。
- 仓库固定在 `~/Projects/Tea`。**严禁把仓库或构建目录放进桌面/文稿等 iCloud 同步路径**——FileProvider/FinderInfo xattr 会让 codesign 报 "resource fork, Finder information, or similar detritus not allowed"（2026-07-23 实测踩坑后搬家），构建垃圾还会上传 iCloud。
