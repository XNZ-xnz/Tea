import CoreGraphics
import Foundation
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
var found = false
for w in list {
    let owner = w["kCGWindowOwnerName"] as? String ?? ""
    if owner.lowercased().contains("wine") || owner.lowercased().contains("steam") {
        found = true
        let name = w["kCGWindowName"] as? String ?? "?"
        let bounds = w["kCGWindowBounds"] as? [String: Any] ?? [:]
        let onscreen = w["kCGWindowIsOnscreen"] as? Bool ?? false
        print("owner=\(owner) name=\(name) bounds=\(bounds) onscreen=\(onscreen)")
    }
}
if !found { print("（没有任何 wine/steam 窗口——窗口根本没被创建）") }
