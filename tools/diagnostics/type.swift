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

// wine 只认真实虚拟键码（转扫描码），unicode 注入收不到——用 ANSI 键码表
let keymap: [Character: (CGKeyCode, Bool)] = [
    "a": (0, false), "b": (11, false), "c": (8, false), "d": (2, false), "e": (14, false),
    "f": (3, false), "g": (5, false), "h": (4, false), "i": (34, false), "j": (38, false),
    "k": (40, false), "l": (37, false), "m": (46, false), "n": (45, false), "o": (31, false),
    "p": (35, false), "q": (12, false), "r": (15, false), "s": (1, false), "t": (17, false),
    "u": (32, false), "v": (9, false), "w": (13, false), "x": (7, false), "y": (16, false),
    "z": (6, false),
    "A": (0, true), "B": (11, true), "C": (8, true), "D": (2, true), "E": (14, true),
    "F": (3, true), "G": (5, true), "H": (4, true), "I": (34, true), "J": (38, true),
    "K": (40, true), "L": (37, true), "M": (46, true), "N": (45, true), "O": (31, true),
    "P": (35, true), "Q": (12, true), "R": (15, true), "S": (1, true), "T": (17, true),
    "U": (32, true), "V": (9, true), "W": (13, true), "X": (7, true), "Y": (16, true),
    "Z": (6, true),
    "0": (29, false), "1": (18, false), "2": (19, false), "3": (20, false), "4": (21, false),
    "5": (23, false), "6": (22, false), "7": (26, false), "8": (28, false), "9": (25, false),
    " ": (49, false), ".": (47, false), "-": (27, false), "=": (24, false), "/": (44, false),
    ",": (43, false), ";": (41, false), "\\": (42, false), "'": (39, false), "`": (50, false),
]
func typeText(_ text: String) {
    for ch in text {
        guard let (code, shift) = keymap[ch] else { continue }
        if shift {
            CGEvent(keyboardEventSource: src, virtualKey: 56, keyDown: true)?.post(tap: .cghidEventTap)
            usleep(20_000)
        }
        let d = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)
        if shift { d?.flags = .maskShift }
        d?.post(tap: .cghidEventTap)
        usleep(40_000)
        let u = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)
        if shift { u?.flags = .maskShift }
        u?.post(tap: .cghidEventTap)
        usleep(40_000)
        if shift {
            CGEvent(keyboardEventSource: src, virtualKey: 56, keyDown: false)?.post(tap: .cghidEventTap)
            usleep(20_000)
        }
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
