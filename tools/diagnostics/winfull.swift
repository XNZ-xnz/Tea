// 列出全部 wine 窗口的 id / pid / 尺寸 / 是否在屏（比 winlist.swift 多给 id 与 pid）
// 用法: winfull.swift [标题过滤词]
import CoreGraphics
import Foundation

let needle = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : nil
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list {
    let owner = (w["kCGWindowOwnerName"] as? String ?? "")
    guard owner.lowercased().contains("wine") else { continue }
    let name = w["kCGWindowName"] as? String ?? ""
    if let n = needle, !name.contains(n) { continue }
    let id = w["kCGWindowNumber"] as? Int ?? 0
    let pid = w["kCGWindowOwnerPID"] as? Int ?? 0
    let b = w["kCGWindowBounds"] as? [String: Any] ?? [:]
    let on = (w["kCGWindowIsOnscreen"] as? Bool) ?? false
    print("id=\(id) pid=\(pid) onscreen=\(on) name=\(name.isEmpty ? "(无标题)" : name) "
        + "w=\(b["Width"] ?? 0) h=\(b["Height"] ?? 0) x=\(b["X"] ?? 0) y=\(b["Y"] ?? 0)")
}
