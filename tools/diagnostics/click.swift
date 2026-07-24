// 向全局坐标注入一次左键点击（需「辅助功能」权限）
// 用法: click.swift <x> <y> [按住毫秒，默认 500]
//
// 为什么要按住这么久：游戏低帧率时（如 5 FPS）每 200ms 才轮询一次输入，
// 常规「按下-80ms-抬起」会被整个漏掉。按住时间必须跨过至少两帧。
// 落点纪律：避开 Steam 窗口区域与屏幕底部 Dock（约 90 点），否则点不到游戏窗口。
import AppKit
import CoreGraphics

guard CommandLine.arguments.count >= 3,
      let x = Double(CommandLine.arguments[1]),
      let y = Double(CommandLine.arguments[2]) else {
    print("用法: click.swift <x> <y> [按住毫秒]")
    exit(1)
}
let holdMs = CommandLine.arguments.count > 3 ? (UInt32(CommandLine.arguments[3]) ?? 500) : 500
let pt = CGPoint(x: x, y: y)
let src = CGEventSource(stateID: .hidSystemState)

// 先移动并停留，让 hover 状态被游戏采样到
CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: pt, mouseButton: .left)?
    .post(tap: .cghidEventTap)
usleep(600_000)
CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: pt, mouseButton: .left)?
    .post(tap: .cghidEventTap)
usleep(holdMs * 1000)
CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: pt, mouseButton: .left)?
    .post(tap: .cghidEventTap)
print("已点击 (\(x), \(y)) 按住 \(holdMs)ms")
