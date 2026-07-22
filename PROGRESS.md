# Tea 进度账本

> 每完成一个阶段更新本文件：当前状态、已定决策、下一步。换新会话先读 CLAUDE.md 再读这里。

## 当前状态

- **阶段**：✅ P0-P3 完成 → **端到端进行中：Steam 已登录（扫码绕行成功），P5R 经 steamcmd 下载中（42GB）**
- **下一步**：下载完成 → relocate-steamcmd-game.sh 1687950 搬进 Steam 库 → 重启 Steam（XoM wine，-silent）→ rungameid 启动 P5R 实测（游戏走 XoM wine 内置 DXMT，D3D 呈现路径已验证正常）

## 🏆 端到端第三夜战记：扫码登录绕行成功（2026-07-23 凌晨-上午）

**Beta 2（26A5388g）没修 CEF 黑屏**——但战役全胜，Steam 已登录（bombpee / XNZ）：

1. **CDP 内窥突破**：Steam 加 `-cef-enable-debugging` → DevTools 协议进入 Chromium 内部——DOM 完全健康（登录页全部控件在），只是画不上屏。诊断法与工具全套在 tools/diagnostics/。
2. **占位码陷阱**：登录页 img 的 QR 起初是 store.steampowered.com 占位码（扫了 3 次失败才识破）——**先本地 Vision 解码验货再发用户**，教训入 README。
3. **第二根因：代理 Fake-IP**——connection_log 见 CM 连接目标 198.18.x.x（Clash 系 Fake-IP 段），Steam 长连接被掐死 → 挑战码永不生成。用户把 steam 域名加 fake-ip 白名单后 CM 连上（hkg 节点）。**Tea 诊断功能必做项：检测 198.18.x = 提示用户改代理配置**。
4. **挑战码狙击**：s.team 码 ~30 秒轮换,「抽码→重生成标准黑白 QR→用户扫」要抢时间；用户手机预先就位 + 重启 Steam 后的新鲜窗口期内狙击成功。
5. **凭据红线全程零违反**：密码零接触，登录确认全在用户手机 Steam App 完成。
6. **安装 API 死角**：SteamClient.Installs 全套（OpenInstallWizard/SetAppList/ContinueInstall/QueueAppUpdate）在前端未挂载状态下均无法真正开始下载（eInstallState 卡 5）——主窗 React 卡 spinner（合成器瘫痪连锁）。**回退 steamcmd**（官方 CLI，无 CEF）：32 位程序需 WineHQ wine 的 wow64（XoM wine 纯 64 位跑不了），在 test prefix 下载中，用户终端自己输密码（合规）。
7. 新知识：Steam 正式承载 UI 的是 SharedJSContext（steamloopback.host），窗口只是投影；`tea steam launch` 的 wine 选型逻辑照旧（XoM wine 首选）。

## ⚠️ Blocker 存档：macOS 27 beta（26A5378n → Beta 2 26A5388g 均未修）的 Chromium 呈现回归（2026-07-23 凌晨定性）

**现象**：Steam 登录窗上屏但内容纯黑（窗口级截屏实证），winedbg 频繁接崩溃。

**排查矩阵（全部实测，全部失败）**：
| wine | 配置 | 结果 |
|---|---|---|
| gptk-wine 3.0-2（CX22） | 默认 | webhelper 循环崩 |
| wine-devel 11.13 + DXMT | GPU | 交换链 EGL_BAD_ALLOC（cef_log） |
| wine-devel 11.13 纯净 | GPU / -cefdisablegpu 软渲染 | 黑屏 |
| wine-devel 11.6_1 满配 | 默认 | 黑屏（该包实为「纯净化」重打包，带补丁的原版 11.6 已被 Gcenx 下架——issue #159 官方确认 11.7 起 DXMT & Steam 不再开箱可用） |
| winecx-xom-5.4.2（CX 系 wine 11 + 内置 DXMT，XoM 用户实战跑 Steam 的同款） | 默认 / -no-cef-sandbox / ForceOpenGLBackingStore | 黑屏 |

**定性证据**：wine GDI 窗口正常（notepad 完整渲染）✓；wine GPU 表面正常（自编 D3D9 清屏 smoke 满窗蓝色）✓；唯 Chromium/CEF 内容全黑 ✗。同款方案社区用户运行正常，但都在 macOS 15/26 稳定版——**结论：27 beta build 26A5378n 与 Chromium ANGLE 呈现链的兼容性回归，非 Tea 架构问题**。

**出路（优先级序）**：
1. **升级 macOS 27 Beta 2（26A5388g，softwareupdate 已见）**——beta 回归的第一解法，待产品负责人执行重启安装
2. 备胎：**steamcmd 绕行**（Valve 官方命令行客户端，纯文本无 CEF：登录+下载游戏全可用；游戏运行走 steam -silent + rungameid，不需要商店 UI）——CEF 黑屏只挡「逛商店」，不挡玩游戏
3. 向 Apple Feedback Assistant 提交（附 D3D9 正常/CEF 黑的对照证据）

**本夜沉淀资产**：winecx-xom-5.4.2 runtime（manifest 已钉，CX 系+内置 DXMT，beta 修复后即为 Steam 首选底座）；诊断工具箱 tools/diagnostics/（窗口清单/窗口级截屏/激活）+ tools/d3d11-smoke/gpu_window_smoke.c（GPU 表面分诊）；per-app 注入全套代码（builtin 标记问题记录在案）。

## 端到端次夜攻坚（2026-07-23 凌晨 2-3 点，Steam UI 三轮排查 + 架构定案）

**Steam UI 复活三部曲（全部 cef_log/实测实证）：**
1. gptk-wine：无 Vulkan → CEF GPU 全灭 → webhelper 循环崩 ✗
2. wine11+DXMT 全局变体：MoltenVK 激活但 CEF/ANGLE 拿 DXMT dxgi 建交换链失败（EGL_BAD_ALLOC）✗
3. **纯净 wine11：CEF 走 wined3d/GL，「Sign in to Steam」登录窗成功上屏 ✓**

**per-app DXMT 的坑（重要工程事实）：**
- DXMT 的 release 与 Actions 全部产物均为 builtin 构建（DLL 带 "Wine builtin DLL" 标记，strings 实证）
- builtin 标记的 DLL 放 prefix system32 + AppDefaults native override **不生效**（wine 认它是 builtin 不是 native，回落 wine 树的 wined3d）——system32 放置 + 注册表写入都验证正确但机制无效
- normal 构建需自编（-Dwine_builtin_dll=false），后置

**双模式架构（v1 定案，待 P5R 下载完成后最终验证）：**
- **逛店模式**：纯净 wine-devel-11.13，Steam UI 完整（登录、商店、下载）
- **游戏模式**：gptk-wine-3.0-2 + `steam -silent`（无 UI，webhelper 崩不阻塞主进程——待验证）+ rungameid，游戏获得 D3DMetal 3（DX10/11/12 通吃，免 per-app 注入）
- 模式切换 = Tea 重启 Steam（几十秒），产品可接受
- **prefix 双向兼容实测通过**：wine11 升级过的 steam prefix 被 gptk-wine（wine8）正常打开（"configuration has been updated" 后 cmd 正常执行）；注意切换前必须清光旧 wineserver（否则 "version mismatch 956/755"）
- wine 窗口不自动上前台（macdrv 特性）：CLI 已内置 CGWindowList+NSRunningApplication 激活逻辑

## 端到端首夜攻坚记录（2026-07-23 深夜实测）

- **症状**：Steam 界面进程 steamwebhelper 循环崩溃（"not responding" 弹窗 + "Failed creating offscreen shared JS context"）
- **根因**：gptk-wine（CX22 基）无 Vulkan（"Wine was built without Vulkan support"），新版 Steam 的 CEF 界面 GPU 路径全灭；`-cefdisablegpu` 单独救不回
- **解法（实测成立）**：Steam 客户端底座切到 **wine-devel-11.13+dxmt-v0.80 变体**——MoltenVK 激活（Vulkan 1.4.334 + 153 扩展 + Apple M4 直识）+ DXMT 提供 d3d11，webhelper 稳定存活（30 秒 pid 不变 ×2 轮验证）
- **策略修订**：DX11 游戏（含 P5R）直接在此底座玩（DXMT 金牌路径回归）；DX12 游戏启动链另行处理（候选：gptk-wine -silent 模式旁路 / 等免费 CX25 系底座）；`SteamManager.defaultRuntime` 自动优先 DXMT 变体
- 附带坑：wine8→wine11 的 prefix 升级会被残余 gptk-wine 进程锁死等待——升级前必须清光旧 wineserver 进程树；Steam 服务（steamservice.exe）会随 wineboot 自启

## 端到端实测操作卡（给产品负责人）

```bash
cd ~/Projects/Tea
.build/debug/tea steam launch        # 打开 Steam 窗口 → 登录（凭据只进 Steam 自己的窗口）
# 在 Steam 里安装《女神异闻录5 皇家版》（约 37GB，注意磁盘）
.build/debug/tea steam apps          # 确认游戏出现在库里
.build/debug/tea steam game 1687950  # 一键启动 P5R
```

## 已定决策

| 日期 | 决策 | 理由 |
|---|---|---|
| 2026-07-23 | 项目名 **Tea**，仓库 `XNZ-xnz/Tea`，bundle id `io.github.xnz-xnz.tea` | 产品负责人拍板；酒（Wine/Whisky）配茶，含义贴切且避开全部禁用词 |
| 2026-07-23 | 仓库 day1 公开 | 开源项目惯例；公开仓库 CI 免费；compat.json 分发依赖公开 Release |
| 2026-07-23 | Core=Swift Package（TeaCore 库 + tea CLI 两个 product），App 经 XcodeGen 引用本地 package | 三层单向依赖的最标准实现 |
| 2026-07-23 | 测试框架用 Swift Testing（非 XCTest） | Xcode 27 原生支持，语法现代 |
| 2026-07-23 | CLI 参数解析用 swift-argument-parser | Apple 官方库，子命令模式现成 |
| 2026-07-23 | `.xcodeproj` 不入库（.gitignore），贡献者跑 `xcodegen` 生成 | 生成物不进版本库，杜绝手改 |
| 2026-07-23 | App Sandbox = NO | 本质是"下载并跑 wine 子进程"，沙箱无法容纳；P6 用公证+Hardened Runtime 保安全 |
| 2026-07-23 | git 身份用 GitHub 匿名邮箱（307991847+XNZ-xnz@users.noreply.github.com） | 避免真实邮箱进公开提交历史 |
| 2026-07-23 | 仓库从桌面搬到 `~/Projects/Tea` | 桌面被 iCloud 云盘同步，FileProvider/FinderInfo xattr 导致 swift test 的 codesign 必然失败（实测），构建垃圾还会上传云端 |
| 2026-07-23 | **Wine 来源改为 Gcenx/macOS_Wine_builds 的 WineHQ 官方构建**（wine-devel 11.13），SHA256 `214e2044…` 已钉入 manifest | 指令首选的 `Gcenx/wine-crossover` 仓库已不存在（GitHub API 404 实测核实）；macOS_Wine_builds 活跃维护（11.13 发布于 2026-07-17），同作者、官方 WineHQ 打包 |
| 2026-07-23 | 数据根支持 `TEA_HOME` 环境变量重定向 | 单元测试与沙盒实验隔离，正常运行仍固定在 ~/Library/Application Support/Tea |
| 2026-07-23 | 快照存 `snapshots/<prefix>/`（prefix 目录之外）；回滚前自动拍 pre-rollback 快照 | 放 prefix 内会被下次快照套娃；自动保底让用户回滚永不丢数据 |

## 环境事实（2026-07-23 实测）

- MacBook Air M4 / 16GB / macOS 27.0 beta（26A5378n）
- Xcode 27.0 beta 4（27A5228h）已装于 /Applications/Xcode-beta.app，license 已接受，xcode-select 已切换
- Rosetta 2 已装；Homebrew 6.0.12；gh 2.96.0 已登录 XNZ-xnz；XcodeGen 2.46.0
- GPTK 4.0 beta 1 dmg：`/Users/xnz/Desktop/Mac Gaming Porting/Game_Porting_Toolkit_4.0_beta_1.dmg`（104,693,519 字节）
- 磁盘可用约 71GB（P3 装游戏实测前需注意，P5R 约需 30-40GB）

## 问题攒单（攒起来一次性问产品负责人）

（暂无）

## 各阶段记录

### P3 Steam 层（2026-07-23 完成）

- **VDF/ACF 解析器**（KeyValues.swift）：Valve KeyValues 文本全子集（引号/嵌套/注释/转义/条件标记/裸词），大小写不敏感查询；fixture 单测覆盖 libraryfolders.vdf 与 appmanifest.acf
- **PE 导入表解析器**（PEImports.swift）：读 exe 导入的 DLL 名猜 DX 版本（默认策略核心）；用自编 d3d11_smoke.exe 当 fixture 单测
- **SteamManager**：官方安装器下载（cdn.fastly.steamstatic.com，HTTPS，运行时获取不分发）→ NSIS /S 静默安装 → launch（-silent 可选）→ steam://rungameid 启动链 → 多库游戏扫描（libraryfolders + acf）
- **recipes 引擎**（Yams）：`recipes/<appid>.yaml` 加载 → LaunchPlan 组装（backend env + recipe env + dll_overrides 合并）；无配方走 PE 导入表默认策略
- **首发 7 款 recipe 种子全部经 Steam 官方 API 核实 appid**（2026-07-23）：P5R=1687950、幸福工厂=526870、天国拯救2=1771300、FH6=2483190、**无尽传奇2=3407390、007初光=3768760、死亡搁浅2=3280350**（后三个为本次查证）
- **真机自测**：`tea steam install` 一次通过（下载→静默装→steam.exe 落位）→ `tea steam launch` → Steam 自更新完成、steamwebhelper（UI 进程）出现、bootstrap 日志 Verification complete → 干净关闭等用户
- recipe→启动方案链路实测：`tea steam game 1687950` 正确输出「后端 d3dmetal，runtime gptk-wine-3.0-2（来源 recipe）」
- 已知限制（v1）：per-game env 只作用于 rungameid 的发起进程；游戏实际继承常驻 Steam 的 env。全局 env 已足够 v1（统一 D3DMetal 3）；per-game env 精确化留待 P4/P5（方案：env 变化时自动重启 Steam）

### P2 图形层（2026-07-23 完成）

**DXMT（DX10/11 默认后端）——全链路实测通过：**
- manifest 新增 dxmt-v0.80（3Shain/dxmt release，SHA256 钉入，包内三目录布局实物核实）
- 装配机制：APFS clonefile 克隆 wine 树成变体 `wine-devel-11.13+dxmt-v0.80`（原版只读不动），按 DXMT 官方 wiki 布局覆盖（winemetal.so → x86_64-unix，d3d11/dxgi/d3d10core/winemetal.dll → x86_64-windows，winemetal.dll 另拷 prefix system32/syswow64）
- **重要架构发现**：DXMT v0.80 新架构（winemetal.so 自包含）不再依赖 CX wine 的 winemacdrv 私有符号（nm 实测：仅标准 unixlib 接口 + 系统框架）——**vanilla WineHQ 构建可直接带动**，wiki 老文档「需要 CX wine」已过时
- 自研 d3d11_smoke.exe（mingw-w64 交叉编译，tools/ 入库）A/B 实测：wined3d = FL 9_3 + 假 GeForce 6800；**DXMT = FL 11_0 + ADAPTER=Apple M4（VENDOR 0x106b）**

**GPTK 导入器——全流程实测通过：**
- GPTK 4.0 beta 1 dmg 实物结构：外层（开发工具）嵌套内层《Evaluation environment for Windows games》dmg，D3DMetal 在内层 `redist/lib/`（与历史版本路径一致）
- 导入器自动处理嵌套挂载 → 布局体检 → 提取 67MB 到 user-provided/gptk/ → 版本解析登记 → 卸载
- **官方环境变量文档抄录入码**（dmg 内 Read Me）：D3DM_SUPPORT_DXR（M1/M2 默认关，M3+ 默认开）、ROSETTA_ADVERTISE_AVX、D3DM_ENABLE_METALFX（macOS 26+）、D3DM_MTL4（macOS 27+）、D3DM_MAX_FPS；shader cache 在 DARWIN_USER_CACHE_DIR/d3dm

**D3DMetal 兼容性结论（三组对照实验，全部实测）：**
- ❌ GPTK 4 库 + vanilla wine 11.13：d3d12.dll 初始化 c0000142（DllMain 挂接 unix 侧失败）
- ❌ GPTK 4 库 + gptk-wine 3.0-2（强制 builtin 同败）：**GPTK 4 库需要 CX24/25 代 wine 底座**，当前无免费活跃构建
- ✅ **gptk-wine 3.0-2 原装全家桶（自带 D3DMetal 3）：D3D12_OK** ——DX12 路线就此打通
- 产品策略：D3DMetal 后端 = gptk-wine 原装；GPTK 4 导入保留登记，等兼容底座出现即启用（关注 Kegworks / CXPatcher 生态）
- manifest 新增 gptk-wine-3.0-2（Gcenx/game-porting-toolkit release，Apple 官方 Read Me 点名的预构建环境；SHA256 与其 tap cask 声称值双源一致）

**其他硬性教训：**
- GPTK 4 的 wine/x86_64-unix/*.so 全是指向 ../../external/libd3dshared.dylib 的**符号链接**——装配必须保持 lib/external 与 lib/wine 平级，否则断链（踩坑：dlopen no such file 但 ls 看似文件在）
- wine 崩溃会拉起 winedbg --auto 弹窗挂死进程树（两次实测踩坑）——WineRunner 已默认注入 winedbg.exe=d，无人值守场景根治
- CX 系 wine 二进制叫 wine64 无 wine；RuntimeManager 已兼容两种命名
- macOS 无 timeout 命令；zsh 里裸 `===`/`==...` 会被当命令

### P1 引擎地基（2026-07-23 完成）

- Core 新增：EnvironmentProbe（sysctl 芯片/内存/系统/Rosetta/磁盘 + 硬件档位判定）、RuntimeManifest+ManifestStore（版本与 SHA256 钉死）、Downloader（仅 HTTPS + 流式 SHA256 + 失败即清）、RuntimeManager（下载/缓存/解包/提取/marker）、PrefixManager（create/delete/clonefile 快照/自动保底回滚）、WineRunner（进程封装 + 日志落盘）
- CLI 实装：env / runtime list·install·remove / prefix list·create·delete·snapshot·snapshots·rollback / run
- 单测 9 个全绿（含真实文件系统 clonefile 快照回滚、SHA256 公开测试向量、HTTPS 强制闸）
- **全链路实测（M4 真机）**：`tea env` ✅ → `tea runtime install wine-devel-11.13`（181MB 下载+校验+安装）✅ → `wine --version` = wine-11.13 ✅ → `tea prefix create test` + wineboot 初始化（system32 生成 848 文件）✅ → `tea run cmd /c echo` 输出正常 ✅ → 快照→破坏→回滚→破坏消失、pre-rollback 自动保底 ✅
- 实物核实：Gcenx tar 包顶层为 `Wine Devel.app`，wine 树在 `Contents/Resources/wine/`（提取逻辑按此实现，兼容裸树布局）
- 待办小项：wine cmd 输出中文乱码（代码页显示问题，不影响功能）；wineboot 的 wineusb.inf 复制警告（Mac 无 USB 驱动需求，无害）

### P0 脚手架（2026-07-23 完成）

- 三层空壳、XcodeGen 工程、CI、CLAUDE.md、本文件、README 草稿、GPL-3.0 全部落地
- 本地 swift build/test + xcodebuild 绿；CI 首跑绿；仓库 https://github.com/XNZ-xnz/Tea 上线
- reference/ 克隆完成：Whisky、Mythic、XIV-on-Mac、dxmt、winetricks、macOS_Wine_builds（221MB，只读参考）
- 踩坑记录：桌面 iCloud 同步导致 codesign 失败 → 仓库定居 ~/Projects/Tea
