import Foundation

public enum RuntimeError: Error, LocalizedError {
    case unknownComponent(String)
    case extractionFailed(String)
    case wineTreeNotFound

    public var errorDescription: String? {
        switch self {
        case .unknownComponent(let id): return "manifest 里没有组件 \(id)。"
        case .extractionFailed(let detail): return "解包失败：\(detail)"
        case .wineTreeNotFound: return "压缩包里没找到 wine 目录（Contents/Resources/wine），包结构可能已变化。"
        }
    }
}

/// 已安装 runtime 的元数据，落盘为安装目录内的 .tea-runtime.json
public struct InstalledRuntime: Codable, Sendable {
    public let id: String
    public let kind: String
    public let version: String
    public let sha256: String
    public let installedAt: Date
}

public enum RuntimeManager {
    static let markerName = ".tea-runtime.json"

    public static func installDir(for id: String) -> URL {
        TeaPaths.runtimes.appendingPathComponent(id, isDirectory: true)
    }

    public static func isInstalled(_ id: String) -> Bool {
        FileManager.default.fileExists(
            atPath: installDir(for: id).appendingPathComponent(markerName).path
        )
    }

    public static func listInstalled() -> [InstalledRuntime] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: TeaPaths.runtimes, includingPropertiesForKeys: nil) else {
            return []
        }
        return entries.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(markerName)) else { return nil }
            return try? decoder().decode(InstalledRuntime.self, from: data)
        }.sorted { $0.id < $1.id }
    }

    /// 下载（或用已校验的缓存）→ 解包 → 提取 → 落位 → 写 marker。
    /// 已安装则直接返回（幂等）。升级 = 装新 id，并排存放（manifest id 含版本号）。
    public static func install(
        _ id: String,
        manifest: RuntimeManifest = ManifestStore.builtin,
        progress: (@Sendable (String) -> Void)? = nil
    ) async throws {
        guard let component = manifest.component(id: id) else {
            throw RuntimeError.unknownComponent(id)
        }
        if isInstalled(id) {
            progress?("\(id) 已安装，跳过")
            return
        }

        let fm = FileManager.default
        let archive = TeaPaths.downloads.appendingPathComponent("\(id).tar.xz")

        // 缓存命中且校验通过则不重复下载
        if fm.fileExists(atPath: archive.path),
           let cached = try? Downloader.sha256Hex(of: archive),
           cached == component.sha256.lowercased() {
            progress?("使用已校验的本地缓存包")
        } else {
            progress?("下载 \(component.url.lastPathComponent)（\(component.sizeBytes / 1_048_576) MB）…")
            try await Downloader.download(component.url, to: archive, expectedSHA256: component.sha256)
            progress?("下载完成，SHA256 校验通过")
        }

        // 解包到临时目录
        let staging = fm.temporaryDirectory.appendingPathComponent("tea-extract-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        progress?("解包中…")
        try untar(archive, into: staging)

        // 按组件类别提取有效载荷
        let payload: URL
        switch component.kind {
        case "wine":
            payload = try locateWineTree(in: staging)
        default:
            // 其他类别 P2 起逐个实现；默认取解包根
            payload = staging
        }

        // 落位 + 写 marker
        try fm.createDirectory(at: TeaPaths.runtimes, withIntermediateDirectories: true)
        let dest = installDir(for: id)
        try? fm.removeItem(at: dest)
        try fm.moveItem(at: payload, to: dest)

        let marker = InstalledRuntime(
            id: id, kind: component.kind, version: component.version,
            sha256: component.sha256, installedAt: Date()
        )
        try encoder().encode(marker).write(to: dest.appendingPathComponent(markerName))
        progress?("\(id) 安装完成")
    }

    public static func remove(_ id: String) throws {
        try FileManager.default.removeItem(at: installDir(for: id))
    }

    /// wine 可执行文件路径（bin/wine）。
    public static func wineBinary(runtimeId: String) -> URL {
        installDir(for: runtimeId).appendingPathComponent("bin/wine")
    }

    // MARK: - 内部

    static func untar(_ archive: URL, into dir: URL) throws {
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-xf", archive.path, "-C", dir.path]
        let stderr = Pipe()
        tar.standardError = stderr
        try tar.run()
        tar.waitUntilExit()
        guard tar.terminationStatus == 0 else {
            let msg = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw RuntimeError.extractionFailed(msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Gcenx 包结构（2026-07-23 实物核实）：顶层 "Wine Devel.app"，
    /// wine 树在 Contents/Resources/wine（bin/lib/share）。做通配查找以兼容命名变化。
    static func locateWineTree(in dir: URL) throws -> URL {
        let fm = FileManager.default
        let tops = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for top in tops {
            let candidate = top.appendingPathComponent("Contents/Resources/wine")
            if fm.fileExists(atPath: candidate.appendingPathComponent("bin/wine").path) {
                return candidate
            }
        }
        // 兼容"直接就是 wine 树"的包
        if fm.fileExists(atPath: dir.appendingPathComponent("bin/wine").path) { return dir }
        throw RuntimeError.wineTreeNotFound
    }

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
