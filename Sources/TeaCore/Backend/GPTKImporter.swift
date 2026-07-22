import Foundation

public enum GPTKError: Error, LocalizedError {
    case mountFailed(String)
    case layoutNotFound
    case notImported

    public var errorDescription: String? {
        switch self {
        case .mountFailed(let d): return "dmg 挂载失败：\(d)"
        case .layoutNotFound: return "dmg 里没找到 redist/lib 布局。请确认这是 Game Porting Toolkit 的 dmg（外层或内层 Evaluation environment 均可）。"
        case .notImported: return "尚未导入 GPTK。到 Apple 官网下载 dmg 后执行 tea backend import-gptk <dmg路径>。"
        }
    }
}

public struct GPTKInfo: Codable, Sendable {
    public let version: String        // 从 dmg 文件名解析，如 "4.0 beta 1"
    public let sourceDMGName: String
    public let importedAt: Date
}

/// GPTK/D3DMetal 导入器。红线 1：D3DMetal 绝不下载、绝不分发——只从用户自备的
/// 官方 dmg 提取到本机 user-provided/ 目录，属 Apple 许可的评估用途。
///
/// GPTK 4.0 beta 1 实物布局（2026-07-23 挂载核实）：
/// - 外层 dmg：开发者工具 + 内层《Evaluation environment for Windows games》dmg
/// - 内层 dmg：redist/lib/{external/{D3DMetal.framework,libd3dshared.dylib},
///             wine/{x86_64-unix/*.so, x86_64-windows/*.dll}}
/// - 与历史版本（redist/lib/）路径一致
public enum GPTKImporter {
    static let markerName = "gptk-info.json"

    public static var importDir: URL {
        TeaPaths.userProvided.appendingPathComponent("gptk", isDirectory: true)
    }

    public static func importedInfo() -> GPTKInfo? {
        guard let data = try? Data(contentsOf: importDir.appendingPathComponent(markerName)) else { return nil }
        return try? RuntimeManager.decoder().decode(GPTKInfo.self, from: data)
    }

    /// 从 dmg 导入 D3DMetal。自动处理外层/内层嵌套。
    public static func importDMG(at dmgPath: URL, progress: (@Sendable (String) -> Void)? = nil) throws -> GPTKInfo {
        progress?("挂载 \(dmgPath.lastPathComponent)…")
        let outerMount = try mount(dmgPath)
        defer { detach(outerMount) }

        var redistLib = outerMount.appendingPathComponent("redist/lib")
        var innerMount: URL?
        defer { if let m = innerMount { detach(m) } }

        if !FileManager.default.fileExists(atPath: redistLib.path) {
            // 外层 dmg：找内层 Evaluation dmg 再挂
            let contents = (try? FileManager.default.contentsOfDirectory(at: outerMount, includingPropertiesForKeys: nil)) ?? []
            guard let inner = contents.first(where: { $0.pathExtension == "dmg" }) else {
                throw GPTKError.layoutNotFound
            }
            progress?("发现内层 \(inner.lastPathComponent)，继续挂载…")
            let m = try mount(inner)
            innerMount = m
            redistLib = m.appendingPathComponent("redist/lib")
            guard FileManager.default.fileExists(atPath: redistLib.path) else {
                throw GPTKError.layoutNotFound
            }
        }

        // 布局体检：关键文件必须在
        let required = [
            "external/libd3dshared.dylib",
            "external/D3DMetal.framework",
            "wine/x86_64-unix/d3d12.so",
            "wine/x86_64-windows/d3d12.dll",
        ]
        for path in required where !FileManager.default.fileExists(atPath: redistLib.appendingPathComponent(path).path) {
            throw GPTKError.layoutNotFound
        }

        progress?("提取 D3DMetal 到本机（约 \( (try? directorySize(redistLib)) ?? 0 ) MB）…")
        let fm = FileManager.default
        try? fm.removeItem(at: importDir)
        try fm.createDirectory(at: importDir.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: redistLib, to: importDir)

        let version = parseVersion(from: dmgPath.lastPathComponent)
        let info = GPTKInfo(version: version, sourceDMGName: dmgPath.lastPathComponent, importedAt: Date())
        try RuntimeManager.encoder().encode(info).write(to: importDir.appendingPathComponent(markerName))
        progress?("导入完成：GPTK \(version)")
        return info
    }

    /// 文件名里解析版本："Game_Porting_Toolkit_4.0_beta_1.dmg" → "4.0 beta 1"
    static func parseVersion(from name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".dmg", with: "")
        if let range = cleaned.range(of: #"[0-9]+(\.[0-9]+)+( ?beta ?[0-9]+)?"#, options: .regularExpression) {
            return String(cleaned[range])
        }
        return "未知版本"
    }

    static func mount(_ dmg: URL) throws -> URL {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        p.arguments = ["attach", dmg.path, "-nobrowse", "-readonly", "-plist"]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errText = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        p.waitUntilExit()
        guard p.terminationStatus == 0,
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let mountPoint = entities.compactMap({ $0["mount-point"] as? String }).first
        else {
            throw GPTKError.mountFailed(errText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return URL(fileURLWithPath: mountPoint, isDirectory: true)
    }

    static func detach(_ mountPoint: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        p.arguments = ["detach", mountPoint.path, "-quiet"]
        try? p.run()
        p.waitUntilExit()
    }

    static func directorySize(_ url: URL) throws -> Int {
        let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
        var total = 0
        while let f = files?.nextObject() as? URL {
            total += (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return total / 1_048_576
    }
}
