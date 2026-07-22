import CoreGraphics
import Foundation
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list {
    let name = w["kCGWindowName"] as? String ?? ""
    let owner = (w["kCGWindowOwnerName"] as? String ?? "")
    if name.contains("Steam") || (owner.lowercased().contains("wine") && !name.isEmpty) {
        print("\(w["kCGWindowNumber"] as? Int ?? 0)\t\(owner)\t\(name)")
    }
}
