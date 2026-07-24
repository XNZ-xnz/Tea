# Tea 进度账本

> 每完成一个阶段更新本文件：当前状态、已定决策、下一步。换新会话先读 CLAUDE.md 再读这里。

## 当前状态

- **阶段**：✅ P0-P3 完成；**降级完成 + 环境重建完成（macOS 26.5.2 / 25F84，Rosetta/Xcode26/gh 全就位）**；🏆 **CEF 黑屏彻底根治，Steam 完整 UI 正常渲染（27beta 噩梦终结）**；⚠️ P5R 游戏进程崩于固定 page fault，端到端最后一环受阻（2026-07-24 凌晨）
- **CEF 黑屏根治（本轮头号成果）**：黑屏与 macOS 版本无关（26/27 双系统同现象），根因是 Steam 2026 客户端 CEF 126 在 wine 上跨进程建交换链 + winsock TLS 双故障。**steamwebhelper 包装器**（`--disable-gpu --single-process`，见 tools/steamwebhelper-wrapper/）一举根治：**Steam 登录态在、商店/库/详情页全部正常渲染（Tears of Metal 商店页、Now Available 弹窗、库均截图实证）**。配套 Steam.cfg `BootStrapperInhibitAll=enable` 防 bootstrapper 还原包装器。
- **Steam 底座矩阵（加包装器后重测）**：✅ 能带 CEF UI = wine-devel-11.13+winemetal 微变体、winecx-xom-5.4.2；❌ webhelper not responding = wine-devel+dxmt-v0.80 完整变体、gptk-wine-3.0-2（即使包装器强制软渲染也救不回，DXMT/gptk 的 d3d 注入把 webhelper 拖垮）
- **P5R blocker（新，未解）**：`tea steam game 1687950` 启动链全通（HasRunKey 跳过 32 位 redist 后 install script 秒过 → P5R.exe 进程起 → 1462×833 窗口上屏），但**窗口纯黑、进程稳定挂起后崩** `Unhandled page fault on read 0x8FF at 0x1401D7EB9`（游戏自身代码固定地址，多次复现）。跨 winecx(DXMT builtin)/wine-devel+winemetal(wined3d 回落)/wine-devel+dxmt 三后端一致；`ROSETTA_ADVERTISE_AVX=1` 实测在 winecx 内确实点亮 AVX（AVX=1 OSXSAVE=1）但**崩溃地址不变**——排除「纯缺 AVX」。崩在图形提交之前，疑似 Denuvo/早期初始化。详见下方「P5R 启动攻坚」。
- **✅ P5R blocker 定性完毕（2026-07-24 凌晨续）**：真凶 = **Denuvo 防篡改激活配额**（弹窗实证 support.codefusion.technology 错误码 88500006）。Denuvo 每天限 5 次激活，**每换一个 wine 底座 = 新硬件指纹 = 烧一次激活**——排查夜连切 6+ 种底座直接烧穿配额。winecx 下的固定 page fault 0x1D7EB9 同源（老 CX 底子上 Denuvo 崩溃式失败，新 wine 下则走到人话弹窗）。
- **🎯 DXVK 图形路线已实证全通**：DXVK-macOS 1.10.3 repack（native PE 无 builtin 标记，覆盖机制有效！）d3d11+d3d10core 放游戏目录 + `WINEDLLOVERRIDES="d3d11,d3d10core=n,b"` + wine 自带 dxgi/MoltenVK → **日志实证 `Using feature level D3D_FEATURE_LEVEL_11_0`、全屏交换链 3×1470×956、CAMetalLayer 挂 WineMetalView**。游戏一路跑到 Denuvo 校验，图形栈零障碍。SHA256 `acd1520ad105d8ef124a09c8e11a259a5dc8bdc565ad18e0e52693f9807b2477`（Gcenx/DXVK-macOS v1.10.3-20230507-repack），待钉入 manifest。
- **下一步（明确路径）**：等 Denuvo 24h 配额重置 → **锁死组合不再切换**：Steam=wine-devel-11.13+winemetal（CEF 包装器）、P5R=同底座+游戏目录 DXVK+`ROSETTA_ADVERTISE_AVX=1` → 一次激活直达标题画面 = P3 端到端达成。此后该 prefix 永不换底座（Denuvo 指纹稳定）。产品层教训：**per-app runtime 切换对 Denuvo 游戏是毒药，Tea 的 recipe 一旦定型底座就要钉死**——这条要进 compat 报告字段与 P4 设计。

## 🏆 里程碑：自建现代 DXVK 打通（2026-07-24 上午，产品负责人接受 Xcode license 后）

**Tea 核心技术资产诞生**：把 2026 最新上游 DXVK（doitsujin/dxvk main，DXVK 3.0.2）现代化到能在
Apple M4 + MoltenVK 1.4.2 + wine-devel 11.13 上跑——**DXVK-macOS 现代化重建首次成功实证**
（社区 Gcenx/DXVK-macOS 停在 2023 的 1.10.3，正是幸福工厂各前序方案撞死的天花板）。补丁+构建+部署
全套入库 `patches/dxvk-macos-m4/`。

**幸福工厂日志深度三连进（=渗透深度实证）**：DXMT 43K → DXVK-macOS 1.10.3 停 139K 死锁 →
**自建 DXVK 逐关突破**：设备建成 FL 11_0 ✓ → 交换链建成 ✓（异种嫁接警告消失）→ 查询崩点修复 ✓。

**打通步骤（全部实测，patch diff 在 patches/）**：
1. 工具链：`brew install meson ninja glslang`（Xcode license 接受后即通；之前系统唯一 python3 是
   Xcode CLT 桩，撞 license 墙连锁瘫痪 meson/glslang/pip——已解）+ mingw-w64 交叉编译。
2. 4 特性门 required→optional（geometryShader/shaderCullDistance/depthClipEnable/robustBufferAccess2+nullDescriptor）
   ——M4 MoltenVK 不报告这些，改后适配器不再被 DXVK 过滤，D3D11 设备建成。
3. 交换链：DLL 需同时放游戏目录**和 prefix system32**（异种嫁接：DXVK 的 dxgi 要被 d3d11 认作同源）。
   ⚠️ system32 部署会污染同 prefix 其他游戏（P5R），**收尾已还原 system32、DXVK 仅留游戏目录**（per-game 正解）。
4. 查询容错补丁：d3d11_query.cpp GetData 对 MoltenVK Invalid/Failed 查询 `continue`（当作完成数据为0）
   而非致命 INVALID_CALL——越过 PollQueryResults 崩点。

**当前边界**：越过查询崩点后深入 RHI 运行时，遇**无调用栈的空指针访问（读 0x0）**。性质已根本改变——
从「无可用 D3D11 转译器」变为「自建 DXVK 可用、剩游戏特定运行时崩」，需调试器级排查（无栈盲补=猜，
不再是"路对不对"而是"具体 bug 猎杀"）。此 DXVK 补丁对所有 DX11 游戏通用。**下一步**：winedbg/lldb
挂栈定位 null-deref，或试 DXVK 老 tag（2.3.x）对比，或换 UE 版本更低的 DX11 游戏先验证栈可玩性。

## 幸福工厂攻坚第三轮：DXMT/3Shain/自建 DXVK（2026-07-24 凌晨 4-5 点）

追加弹药 7-13，全部实测存档。**结论没变但把每条路的确切拦点钉死了**：

| # | 弹药 | 拦点 |
|---|---|---|
| 7 | wine-devel+dxmt-v0.80 完整变体 | `Failed to create metal view: Wine has no exported symbols needed by DXMT`——Gcenx WineHQ 构建的 winemac.so 零导出（修正 P2 nm 静态分析漏了 dlsym 动态探测的错误结论） |
| 8 | winecx-xom-5.4.2（自带配对 DXMT） | 三次全僵死在进程孵化阶段（零日志零窗口）——winecx 跑 Steam/P5R 正常，独此 UE5 exe 起不来 |
| 9 | **3Shain wine 9.9**（专为 DXMT 导出符号的 fork）× 树内置 DXMT | 启动器 VC redist 弹窗死循环——**3Shain 是 wine 9.x，比 wine-devel 11.13 老，对 UE5.3 启动器的 prereq 检测有兼容回归**；伪造 VC 注册表全变体无效 |
| 10 | 3Shain 直跑 Shipping exe（绕过启动器） | `c0000135`（UE5 shipping 依赖链更深，补 steam_api64/ogg/vorbis/aftermath 仍不足） |
| 11 | **自建上游 DXVK 2.x**（mingw 交叉编译 PE DLL，理论直击 1.10.3 死锁天花板） | **硬 blocker：Xcode license 未接受**——系统唯一 python3 是 Xcode CLT 桩，每次调用即撞墙，连带 meson（要 python）/glslang（要编译）/pip 全瘫。ninja 预编译已拿到，DXVK 源码已 clone（doitsujin/dxvk main），就差工具链 |

**需要产品负责人一条命令解锁弹药 11**（要密码，Claude 无法代办）：
```
sudo xcodebuild -license accept
```
接受后自建现代 DXVK 全链条即通（源码/ninja/mingw 已就位，只差 meson+glslang，届时可从 wheel/预编译补齐）。这是**目前唯一直击已证实天花板（DXVK 1.10.3 首帧死锁）的主动路线**，成算最高。

**已入库资产（跨会话可复用）**：`wine-3shain-9.9` runtime（带导出符号，等 DXMT 新版或修 UE5 启动器兼容后可用）、`wine-devel-11.13+winemetal+mvk142`（MoltenVK 1.4.2）、DXVK 源码树、ninja 二进制、DXMT dxmt-72 全套 DLL。

## 幸福工厂攻坚第二轮：六发弹药矩阵（2026-07-24 凌晨 3-4 点，全部实测存档）

前一轮四路线定性后追加六发针对性弹药，全部失败但把死锁定位到了**组件级**：

| # | 弹药 | 结果与证据 |
|---|---|---|
| 1 | gptk D3DMetal DX11 + `-graphicsadapter=0` | 仍 `bFoundMatchingDevice` 断言——D3DMetal dxgi 枚举与 UE 设备匹配根本不兼容 |
| 2 | DXVK 直接加载世界 + `MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS=1` | 同点冻结（log≈131KB）——排除队列异步提交因素 |
| 3 | 完整 DXVK 含自家 dxgi + dxvk.conf AMD 伪装 | wine 对 dxgi 的 native 覆盖未生效（nvapi 仍被调用），同点冻结 |
| 4 | 全最低画质（sg.*=0 + r.* 精简） | **推进最远**（log 139KB vs 131KB）但仍冻——死锁在必经管线，非重型特效 |
| 5 | **MoltenVK 升级 1.2.7→1.4.2**（新变体 wine-devel-11.13+winemetal+mvk142，已入库可复用） + DXVK | 同 139KB 冻结——**排除 MoltenVK，元凶锁定 DXVK 1.10.3 自身转译死锁** |
| 6 | `-vulkan` × MoltenVK 1.4.2（正常启动） | 仍实例创建死锁（log 59KB，比 DXVK 死点早）——UE Vulkan RHI 的死结在 winevulkan 层，MVK 升级无关 |

**追加弹药 7/8（2026-07-24 凌晨 4-5 点）**：
- 弹药7 = wine-devel+dxmt-v0.80 完整变体带游戏：RHIThread 崩溃，stderr 实锤 **`Failed to create metal view, it seems like your Wine has no exported symbols needed by DXMT`**——修正 P2 时代错误结论：nm 静态导入分析漏了 winemetal 的 dlsym 动态探测，**DXMT 在 Gcenx WineHQ 构建上无法工作**（winemac.so 零导出符号）。修复路径明确：notpop 的 08-patch-wine-visibility 方案 / 3Shain wine 构建（导出 17 个符号，nm 证据在其仓库）——**下次会话的第一弹药**。
- 弹药8 = winecx（自带配对 DXMT）带游戏：三次尝试全部僵死在进程孵化阶段（零输出、零窗口、UE 日志未开）——独立怪癖待查（winecx 跑 Steam 正常、跑 P5R 能到崩溃点，唯独这个 UE5 exe 起不来）。过程坑：**gptk-wine 的 services/plugplay/svchost/rpcss/explorer 服务树不匹配常用 pkill 模式**（要用 `pkill -f wine64-preloader`），残留会霸占 prefix 让新 wine 全部僵死——进 Tea 的进程管理必修课。

**最终定性**：幸福工厂（UE5.3 世代）在当前免费栈的三堵墙：①DX11 唯一可渲染路线（DXVK）死于 **DXVK-macOS 1.10.3（2023 停更）的转译死锁**，且与场景无关（菜单/世界同死点）、与画质无关、与 MoltenVK 版本无关 ②Vulkan RHI 死于 winevulkan 层实例创建 ③DX12 死于 D3DMetal 缺 CX 代 wine 胶水（采样器堆/LUID 双断言）。**出路只剩上游**：DXVK-macOS 现代化重建（VK1.3×MVK1.4 时机已成熟，可自建或催社区）> CX26 系免费衍生底座 > DXMT 补全 UE5 特性。

**产品方向确认（产品负责人 2026-07-24 拍板）**：①不接受绕过游戏菜单/EULA 的方案上产品——用户必须能正常点击游戏自己的界面，直接加载地图只作诊断探针 ②兼容目标改为「某一类型游戏 90% 能进游戏界面」的泛用性，选题从免费栈已验证的 DX11 世代游戏清单入手，UE5 级硬骨头交给底座演进 ③接受「底座工程 + 精选清单 + 配方长尾」打法（Proton/protonfixes 同构），放弃「万能转译层白拿全兼容」幻想。

## 幸福工厂攻坚战报（2026-07-24 凌晨，四路线定性完毕）

**成果**：CDP 全自动装机 ✓、28.21GB 下载完成 ✓、**游戏引擎实际渲染出画面**（splash/加载屏/菜单加载，DXVK 路线）——但四条图形路线全部在不同深度受阻，暂无法进主菜单交互。逐条存档：

| 路线 | 结果 | 死因（全部实测定位） |
|---|---|---|
| `-vulkan`（UE5 原生 Vulkan→winevulkan→MoltenVK） | 引擎挂起 | UE Vulkan RHI 实例创建死锁（日志停在 "Found 0 available instance layers"，CPU 全 0%；DXVK 同栈能建设备，是 UE 的初始化路径触发） |
| `-dx11` + DXVK 1.10.3（游戏目录 native） | **最接近成功**：splash+加载屏正常渲染数分钟、菜单 widgets 加载完成 | 菜单首个真实 3D 帧（帧号[2]）GPU 命令缓冲死锁。全屏/窗口化/关 SkyLight 实时反射/DXVK_ASYNC 四变量矩阵全试，冻结点不变 |
| DX12 + D3DMetal 3（gptk-wine 原装） | RHIInit 即崩 | `Assertion failed: GGlobalSamplerDescriptorHeapSize <= MaximumSamplerHeapSize`——UE5.3 全局采样器堆 2048 硬编码 > D3DMetal 上限；Engine.ini cvar 在 RHIInit 后加载，救不了 |
| `-dx11` + D3DMetal 3 | RHI 选择即崩 | `Assertion failed: bFoundMatchingDevice`——D3DMetal 的 dxgi 枚举与 D3D11 设备 LUID 对不上 |

**过程沉淀（全部可复用）**：
- **CDP 全自动装机**：`-cef-enable-debugging` → SharedJSContext → `OpenInstallWizard([appid])` → `ContinueInstall()`，零人工。P4「一键安装」机制原型。
- **下载停滞诊断链**：Steam UI 0bps → content_log `ContentServerDirectoryService failed` + CDN 域名 `xz.pphimalayanrt.com` 解析 0.0.0.0（DNS 污染）→ 宿主网络正常 → **重启 Steam 换新 CM 连接即愈**（CDP `PauseAppUpdate/ResumeAppUpdate` 不够）。诊断功能（5.4）新增检测项。
- **VC++ 2015-2022 x64 运行库缺失**：HasRunKey 跳过 redist 的副作用；游戏启动器弹窗要装。解法：跑 Steam 自带 `_CommonRedist/vcredist/2022/VC_redist.x64.exe /install /quiet /norestart`（x64 安装器 wine 可跑，32 位才跑不了）。**Tea 应在 prefix 初始化时默认预装**。
- gptk-wine（CX 系）Windows 用户名是 `crossover` 不是 `xnz`——AppData/日志路径随 wine 切换，排查时必须跟着换。
- `steam -silent` 下 webhelper 弹窗（not responding）照常出现但**不阻塞** steam.exe 核心与游戏进程；游戏 SteamAPI init 失败（conditions not met）也照样跑（Satisfactory DRM 极轻）。
- 监控体系定型：常驻 watchdog（进程/窗口/下载指纹 + 600s 停滞报警 + 对话框即报）+ 每实验三重指标（UE 日志尺寸 + 截图字节 + 进程数）。两次抓到人工漏看的对话框。

**后续方向（按优先级）**：① DXVK 路线只差最后一步——试 DXVK 2.x 新版（MoltenVK 1.3 特性成熟后）或 MVK_CONFIG 参数矩阵攻菜单首帧死锁 ② 等 DXMT 支持 UE5 全特性 ③ D3DMetal 采样器堆问题上报 Apple Feedback（附断言证据）④ 关注 CX26 免费衍生底座（AppleGamingWiki 记 CX26.1 可跑）。

## 幸福工厂攻坚（2026-07-24 凌晨续）：CDP 全自动装机成功

- **SteamClient.Installs API 在前端挂载后完全可用**（第三夜的 eInstallState 卡 5 死角只存在于前端未挂载状态）：`-cef-enable-debugging` 起 Steam → SharedJSContext → `OpenInstallWizard([526870])` 弹出渲染完好的安装向导（Satisfactory 28.21GB / C 盘 95.62GB）→ `ContinueInstall()` 确认 → 下载启动。**全程零人工点击**——这就是 P4「一键安装」的机制原型。
- 幸福工厂无 Denuvo，换底座无激活配额风险。启动路线：首选 recipe 外的 `-vulkan` 启动项（UE5 Vulkan RHI→winevulkan→MoltenVK，与 Steam 同底座免切 wineserver）；备选 recipe 的 gptk-wine+D3DMetal 3（难点：gptk 下 Steam webhelper not responding，需验证 -silent 核心是否够 steam_api 握手）。
- 监控升级：常驻 watchdog（30s 指纹比对：进程/窗口/下载字节；变化才报事件；**600s 无变化强制 STALLED 报警**；小对话框即时上报）——修复前两轮漏看对话框的问题。

## 🏆 CEF 黑屏根治 + P5R 启动攻坚（2026-07-24 凌晨，降级后首夜）

### 环境重建（macOS 26.5.2）全绿
- 数据备份关键坑：用户把 51GB 备份恢复到系统级 `/Library/Application Support/Tea`，Tea 读的是用户级 `~/Library`——同卷 mv 搬回即全部识别（steam prefix 43GB 含登录态 + P5R 39.4GB、9 个 runtime、GPTK 提取物）。
- Rosetta 2 / Xcode 26.6（17F113）/ gh 已登录 XNZ-xnz / brew(xcodegen,gh,mingw-w64) 全就位；`swift build` 绿（命令行工具 Swift 6.3.2 即可，`swift test` 需完整 Xcode 的 Testing 模块）。
- git 用 `/opt/homebrew/bin/git` 绕开 Xcode license 未接受（`xcodebuild -license` 需用户 sudo，未做，不影响 swift build/git）。

### 🎯 CEF 126 黑屏根治（Tea 里程碑）
- **定性升级**：黑屏在 macOS 26 稳定版**依旧复现**——推翻「27 beta 回归」旧结论。真根因 = Steam 2026 客户端 CEF 126 在 wine 上的两个跨版本故障：①渲染进程跨进程建 D3D11 交换链撞 DXMT #141 → 画黑 ②NetworkService 独立进程走 wine winsock TLS → `handshake failed net_error -100`。
- **解法**：`steamwebhelper` 包装器（源自 [notpop/steam-on-m1-wine](https://github.com/notpop/steam-on-m1-wine) MIT，入库 tools/steamwebhelper-wrapper/）。改名 Valve 原版为 `steamwebhelper_real.exe`，包装器顶替原名，每次调用前插 `--disable-gpu --single-process` 转发。实测 `ps` 见 `steamwebhelper_real.exe --disable-gpu --single-process` 生效，**Steam 商店/库/详情全部正常上屏（多张截图实证）**。
- **两参数缺一不可**：`--disable-gpu` 单用（=`-cefdisablegpu`）仍黑；`NetworkServiceInProcess` 单用被 CEF 126 忽略。
- **防还原**：Steam bootstrapper 启动时校验会还原原版包装器 → 写 `Steam/Steam.cfg` `BootStrapperInhibitAll=enable` 抑制；tea 未来 launch 前应按体积（Valve 原版 >6MB，包装器 <200KB）校验并自愈重装（逻辑见来源仓库 06-install-wrapper.sh）。

### ⚠️ P5R 启动攻坚（未破，blocker 存档）
- **启动链已全通**：recipe→dxmt 后端→winecx；首次卡 `RunningInstallScript`（32 位 vcredist/DirectX redist 的 .cmd 在纯 64 位/无 cmd 环境跑不动）——**写 HasRunKey 注册表**（`HKLM\Software\Valve\Steam\Apps\CommonRedist\{vcredist\2019,DirectX\Jun2010}` 各 DWORD=1）跳过 → install script 秒过 → P5R.exe 起、1462×833 窗口上屏。
- **崩溃现象（多后端一致）**：窗口纯黑、进程挂起 ~数分钟后 `wine: Unhandled page fault on read access to 0x8FF at address 0x1401D7EB9`（游戏镜像基址 0x140000000 + 0x1D7EB9，固定复现）。winedbg 无法自启（`--auto` 报 126）→ 进程僵死不退，靠外部 kill。
- **已排除**：`ROSETTA_ADVERTISE_AVX=1` 实测在 winecx 内点亮 AVX（自编 cpuid.exe：无 flag AVX=0，有 flag AVX=1 OSXSAVE=1），但崩溃地址不变 → 不是「纯缺 AVX」。Steam overlay DLL（GameOverlayRenderer64）禁用无效。P5R 的 AppDefaults DXMT override 清掉、prefix system32 DXMT DLL 清掉再 wineboot 重生 builtin 均无效。
- **后端对照**：winecx（DXMT builtin d3d11，游戏能 load d3d11 但崩）；wine-devel+winemetal（无 native d3d11 覆盖→游戏回落 wined3d→`None of the requested D3D feature levels supported`）；wine-devel+dxmt 完整变体（Steam webhelper 直接 not responding，游戏 SteamAPI init 失败退出）。
- **崩点判断**：page fault 在图形提交之前（DLL 刚加载完 steamclient64/kerberos 等，未见 d3d 设备创建日志），指向游戏早期逻辑/反作弊，**疑似 Denuvo**（P5R 带 Denuvo）或 CPU 特性探测的二次分支。
- **最有据出路**：AppleGamingWiki 记 P5R 在 **CrossOver 评级「Perfect」，方法明确是「Turn on DXVK」**（D3D11→Vulkan→MoltenVK 路线）；Wine 原生评级「Unplayable, doesn't boot」。Tea 全底座走 DXMT（D3D11→Metal），可能正是 P5R 不兼容点。搭 DXVK + MoltenVK 底座为首选下一步（老难点：native d3d11 覆盖需非 builtin 标记 DLL）。

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

- MacBook Air M4 / 16GB / macOS 26.5.2（25F84，2026-07-23 降级完成）
- Xcode：**未装**（仅命令行工具，Swift 6.3.2——swift build 可用，swift test 缺 Testing 模块需完整 Xcode 26）
- Rosetta 2 **未装**（降级后系统全新，wine 硬前提）；Homebrew 已装；gh 2.96.0 **未登录**；XcodeGen 已装；mingw-w64 已装
- GPTK 4.0 beta 1 dmg：`/Users/xnz/Desktop/Mac Gaming Porting/Game_Porting_Toolkit_4.0_beta_1.dmg`（104,693,519 字节）
- 磁盘可用约 97GB；Tea 数据（51GB）已在 ~/Library/Application Support/Tea 就位

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
