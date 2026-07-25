# sentinel — Claude Code 自我监控哨兵

单文件 `sentinel.py`,python3 标准库零依赖,只调系统自带命令。
状态与产物:`$TEA_HOME/sentinel/`(jobs/、shots/、state.json、inbox.md、offsets.json)。

## 设计原则(五条)
1. **判决优先**:每个命令第一行 `VERDICT: <状态>`,附证据与建议;`--json` 机读全量。
2. **上下文经济**:默认 ≤30 行;细节落盘只回路径,agent 按需 view。
3. **新鲜度由工具保证**:时间戳/md5/字节偏移由哨兵记账,"自上次以来"是原语。
4. **熔断是功能**:预算/计数到线主动 ESCALATE,"该停了"从自觉变机制。
5. **自体检**:`sentinel selftest` 全绿才可信。

## 命令面
任务判活:`run <name> [--profile shader|download|compile|boot] -- <cmd>` / `jobs` /
`watch <job|pid>`(五态:RUNNING_HEALTHY/RUNNING_SILENT/LIKELY_HUNG/DEAD/DONE)/
`logs <job|file>`(增量+签名打标,签名库与 diagnostics/rules/ 同源)
感知清场:`shot [--tag]`(黑屏嫌疑+冻结启发式,语义判断 view 图)/ `ps` / `purge` / `doctor`
纪律协作:`state [--set k=v]` / `guard denuvo <appid> [--record]` /
`budget start <名> --minutes N` `budget check` / `attempt <指纹>` /
`handoff --need <一句话>` / `inbox` / `selftest`

## 使用纪律(CLAUDE.md 哨兵条款八条,此处不重复)

## 人类一次性设置
- 给终端授予「屏幕录制」权限(截图需要):系统设置→隐私与安全性→屏幕录制
- (可选)osascript 焦点检测需「辅助功能」权限

## 边界
不替人做审美判断、账号登录、花钱决策——只把这三类真介入变成异步交接卡。
不进 Tea 发布物、不碰产品代码、不需要网络。
