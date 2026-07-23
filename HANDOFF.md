# Tea 项目交接文档（macOS 27 beta → 26 降级专用）

> 写于 2026-07-23。给降级后的新环境、新 Claude 会话。
> 新会话开工咒语：「继续 Tea 项目，先读 ~/Projects/Tea/CLAUDE.md 和 PROGRESS.md 和 HANDOFF.md」。

## 一、为什么降级

macOS 27 beta（26A5378n 与 Beta 2 26A5388g 均确认）存在 Chromium/CEF 呈现回归：wine 里任何 CEF 内容窗口纯黑（Steam 界面全灭），而 GDI 窗口与 D3D/GPU 表面完全正常（附证据：notepad 正常渲染、自编 D3D9 清屏 smoke 满窗蓝色、CDP 内窥 DOM 完全健康）。跨 4 种 wine × 6 种渲染配置全部复现，排查矩阵见 PROGRESS.md。macOS 26 是 Tea 部署目标，CX/XoM 社区在 26 上运行正常。

**降级后第一件事**：起 Steam 看登录窗是否正常渲染——正常即宣告全部「盲操作杂技」退役。

## 二、降级前备份清单（产品负责人执行）

| 内容 | 位置 | 处置 |
|---|---|---|
| 代码仓库 | ~/Projects/Tea | ✅ 已全部推 GitHub（XNZ-xnz/Tea），无需备份 |
| 原始指令 + GPTK dmg | 桌面 Mac Gaming Porting 文件夹 | 用户手动复制（GPTK dmg 也可从 Apple 官网重下） |
| **Steam 登录态 + P5R 39GB** | `~/Library/Application Support/Tea/prefixes/steam`（约 45GB） | **可选**：有外置盘就整目录拷走，恢复后免重下 42GB 免重登录；没有就放弃，流程全自动可重来 |
| runtimes（wine 们） | ~/Library/Application Support/Tea/runtimes | 不备份，manifest 一键重装 |

## 三、新环境重建清单（30-60 分钟）

1. 装 Xcode（macOS 26 上装 **Xcode 26 稳定版**即可，App Store 或 developer.apple.com）→ 打开一次让它装组件 → `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
2. Homebrew（官网一行命令）→ `brew install xcodegen gh mingw-w64`
3. `gh auth login`（GitHub 账号 XNZ-xnz，浏览器授权）
4. `git clone https://github.com/XNZ-xnz/Tea ~/Projects/Tea`（**必须放 ~/Projects，严禁桌面/文稿——iCloud 会毁构建**）
5. `cd ~/Projects/Tea && swift build && swift test`（期待 16 测试全绿）
6. git 身份：`git config --global user.name XNZ-xnz && git config --global user.email 307991847+XNZ-xnz@users.noreply.github.com`
7. 参考仓库（可选，Claude 需要时自己克隆）：Whisky、Mythic、XIV-on-Mac、dxmt、winetricks、macOS_Wine_builds → reference/（.gitignore 已排除）

## 四、Tea 数据目录重建

```bash
cd ~/Projects/Tea
.build/debug/tea env                                # 环境自检
.build/debug/tea runtime install winecx-xom-5.4.2   # Steam 与游戏的主力 wine（CX 系+内置 DXMT）
.build/debug/tea runtime install wine-devel-11.13   # 通用 wine（steamcmd 等 32 位程序用它的 wow64）
# 可选：gptk-wine-3.0-2（D3DMetal 3 全家桶，DX12 游戏用）、dxmt-v0.80
```

- 恢复了 steam prefix 备份：整目录放回 `~/Library/Application Support/Tea/prefixes/steam`，直接 `tea steam launch`
- 没备份：`tea steam install` 重装 → 登录（这次窗口可见，正常登录）→ P5R 重新下载（Steam 客户端内直接下，或 steamcmd 流程见 tools/diagnostics/README）

## 五、当前进度快照（交接时刻）

- **P0-P3 全部完成**：三层架构、runtime 管理、prefix 快照、双图形后端实测、Steam 集成、VDF/ACF 解析、recipes 引擎、16 单测 + CI 绿
- **端到端走到 95%**：扫码登录成功（凭据零接触）、P5R 39GB 已下载并被 Steam 认领（`tea steam apps` 识别正常）、启动链走到 **EULA 确认**（产品负责人已口头确认同意）——27beta 下 EULA 弹窗不可见而卡住，降级后在可见窗口里点一下 Accept 即过
- **P5R 启动配方已定**：recipes/1687950.yaml → winecx-xom-5.4.2（内置 DXMT，DX11 完整能力实测 FL 11_0 + Apple M4 直通）
- 已知残留：`SteamClient.Apps.MarkEulaAccepted` API 已定位未使用（降级后应无需）；Steam Service 启动失败（GLE 183，wine 常态，暂未见阻塞）

## 六、降级后行动序列

1. 环境重建（第三节）+ 数据重建（第四节）
2. `tea steam launch` → **验证登录窗正常渲染**（27beta 噩梦终结的标志）
3. 登录（有备份则已在）→ P5R 就位 → `tea steam game 1687950` → EULA 点 Accept → **游戏进标题画面 = P3 端到端正式达成**
4. 补测：幸福工厂（DX12 / gptk-wine / D3DMetal 3）
5. 写首批第一方兼容报告（compat/reports/，字段规范见 compat/README.md）
6. 进 P4 GUI（首次运行向导 → 主界面 → 详情页 → 设置 → 诊断；每个界面可用即叫产品负责人看设计）

## 七、这三天沉淀的产品级知识（设计 P4/P5 时直接取用）

1. **诊断功能（5.4）必做检测项**：①代理 Fake-IP 掐死 Steam 长连接（connection_log 见 198.18.x.x → 提示用户把 steam 域名加 fake-ip-filter）②CEF 黑屏（beta 系统回归检测）③Steam Service 失败（GLE 183，说明性提示）
2. **wine 生态地图**：WineHQ 官方构建（Gcenx 打包）11.7 起不再带 DXMT/Steam 补丁；XoM 的 winecx 是活跃免费 CX 系构建（内置 DXMT，纯 64 位）；gptk-wine 3.0-2 = D3DMetal 3 全家桶（32on64）；DXMT 官方产物全是 builtin 标记版（native 注入无效）
3. **首次运行向导（5.1）新增环节**：EULA 代理确认没必要做——窗口可见时用户自己点
4. tools/diagnostics/ 工具箱：窗口检测、CDP 内窥、QR 解码/生成、GPU 表面 smoke——全部实战验证过
