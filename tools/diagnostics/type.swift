// 向前台窗口注入按键/文本（需「辅助功能」权限）
// 用法:
//   type.swift key <keycode>        按一次指定虚拟键（50=反引号` 36=回车 53=Esc）
//   type.swift text "some text"     逐字符输入文本（Unicode 注入，无视键盘布局）
//   type.swift line "r.Foo 1"       输入文本并回车
import CoreGraphics
import Foundation

let src = CGEventSource(stateID: .hidSystemState)

func pressKey(_ code: CGKeyCode) {
    CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)?.post(tap: .cghidEventTap)
    usleep(60_000)
    CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)?.post(tap: .cghidEventTap)
    usleep(60_000)
}

func typeText(_ text: String) {
    for ch in text.unicodeScalars {
        var u = [UniChar(ch.value)]
        let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)
        down?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &u)
        down?.post(tap: .cghidEventTap)
        usleep(30_000)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
        up?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &u)
        up?.post(tap: .cghidEventTap)
        usleep(30_000)
    }
}

guard CommandLine.arguments.count >= 3 else {
    print("用法: type.swift key <keycode> | text <str> | line <str>")
    exit(1)
}
let mode = CommandLine.arguments[1]
let arg = CommandLine.arguments[2]
switch mode {
case "key":  pressKey(CGKeyCode(UInt16(arg) ?? 50))
case "text": typeText(arg)
case "line": typeText(arg); usleep(100_000); pressKey(36)
default: print("未知模式"); exit(1)
}
print("完成: \(mode) \(arg)")
