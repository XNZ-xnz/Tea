import AppKit
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list {
    let name = w["kCGWindowName"] as? String ?? ""
    if name.contains("Steam"), let pid = w["kCGWindowOwnerPID"] as? pid_t {
        NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows])
        print("已激活 pid \(pid)（窗口: \(name)）")
    }
}
