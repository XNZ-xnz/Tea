# 诊断工具箱

macOS 27 beta「CEF 渲染瘫痪」战役中锻造的无头驱动工具（2026-07-23）。全部为独立 Swift 脚本，`swift <脚本> <参数>` 直接运行。

## 窗口层
- `winlist.swift` — 列出 wine/Steam 的全部窗口（位置、是否在屏）
- `winid.swift` — 窗口标题 → windowID（配合 `screencapture -l` 做窗口级截屏）
- `activate.swift` — 把 wine 窗口激活到前台（macdrv 不抢焦点的对策）

## CEF/Chromium 内窥（Steam 加 -cef-enable-debugging 后用）
- `cdp-shot.swift <ws-url> <out.png>` — DevTools 协议截取页面（绕过屏幕合成器）
- `cdp-eval.swift <ws-url> <js>` — 页面内执行 JS 取值
- `cdp-eval-async.swift <ws-url> <js>` — 同上，等待 Promise

## 二维码
- `qr-decode.swift <img>` — Vision 框架本地解码（验货必用：先解码确认内容再给用户）
- `qr-gen.swift <text> <out.png>` — 从文本生成标准黑白 QR（CIQRCodeGenerator）

## 经典组合拳（Steam 扫码登录全程无头）
1. Steam 带 `-cef-enable-debugging` 启动 → `curl localhost:8080/json` 拿页面 ws
2. cdp-eval-async 抽登录页 QR blob → qr-decode 验明是 s.team 挑战码（占位码是 store 链接，别发！）
3. qr-gen 重新生成标准码 → 发用户手机扫
4. 注意挑战码 ~30 秒轮换，抽码到扫码要抢时间
