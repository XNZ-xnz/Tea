# Tea 进度账本

> 每完成一个阶段更新本文件：当前状态、已定决策、下一步。换新会话先读 CLAUDE.md 再读这里。

## 当前状态

- **阶段**：✅ P0、✅ P1 完成（2026-07-23）→ P2 图形层进行中
- **构建**：本地 9 测试全绿；P1 CLI 全链路实测通过（见 P1 记录）
- **下一步**：P2——DXMT 来源核实与装配（先读 reference/dxmt 文档）→ GPTK dmg 解包提取 D3DMetal → 后端切换机制

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
