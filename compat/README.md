# compat/

兼容性数据即文件：

- `games/*.yaml` — 每游戏条目（徽章、硬件档位、requires_gptk 等）
- `reports/*.yaml` — 实测报告（chip / memory / macos / runtime 版本 / game_build / date / source: first-party|community / evidence 链接 / settings / notes）

规则（红线）：

- 每份报告必须有出处：第一方实测，或附链接的社区证据。找不到出处保持 Unknown。
- 禁止虚构，禁止把推断写成实测。
- 游戏 `current_build` 变更后旧报告转「待复验」。
- 低档实测结论 X ⇒ 高档显示「至少 X（推断）」；反向不推断。

CI 将把这些文件汇编成 `compat.json` 随 Release 发布，App 启动时拉取 + 本地缓存 + 内置快照兜底（P5 落地）。
