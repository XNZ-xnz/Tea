# Tea 进度账本

> 每完成一个阶段更新本文件：当前状态、已定决策、下一步。换新会话先读 CLAUDE.md 再读这里。

## 当前状态

- **阶段**：✅ P0、✅ P1、✅ P2 完成（2026-07-23）→ P3 Steam 层进行中
- **构建**：本地 10 测试全绿；两大图形后端均在 M4 真机实测通过（DXMT: FL 11_0 + Apple M4 直通；D3DMetal 3: D3D12_OK）
- **下一步**：P3——SteamSetup.exe 获取与静默安装 → VDF/ACF 解析器（fixture 单测）→ rungameid 启动链 → recipes 引擎 → 端到端节点叫产品负责人

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
