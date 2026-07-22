import Foundation
import Darwin

public enum PrefixError: Error, LocalizedError {
    case alreadyExists(String)
    case notFound(String)
    case snapshotNotFound(String)
    case cloneFailed(String, Int32)

    public var errorDescription: String? {
        switch self {
        case .alreadyExists(let n): return "prefix「\(n)」已存在。"
        case .notFound(let n): return "prefix「\(n)」不存在。"
        case .snapshotNotFound(let n): return "快照「\(n)」不存在。"
        case .cloneFailed(let path, let errno):
            return "APFS 克隆失败（errno \(errno)）：\(path)。快照功能要求 APFS 卷。"
        }
    }
}

public struct PrefixInfo: Sendable {
    public let name: String
    public let url: URL
    public let createdAt: Date?
}

public struct SnapshotInfo: Sendable {
    public let name: String       // 目录名：<ISO时间戳>_<label>
    public let label: String
    public let url: URL
}

/// prefix 生命周期：创建/删除/快照/回滚。
/// 快照用 APFS clonefile：整棵目录树写时复制，秒级完成、初始零磁盘成本。
public enum PrefixManager {
    public static func prefixDir(_ name: String) -> URL {
        TeaPaths.prefixes.appendingPathComponent(name, isDirectory: true)
    }

    static func snapshotRoot(_ name: String) -> URL {
        TeaPaths.appSupport.appendingPathComponent("snapshots", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }

    public static func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: prefixDir(name).path)
    }

    /// 只建目录与登记；wine 环境初始化（wineboot）由首次运行 wine 时触发。
    public static func create(_ name: String) throws {
        guard !exists(name) else { throw PrefixError.alreadyExists(name) }
        try FileManager.default.createDirectory(at: prefixDir(name), withIntermediateDirectories: true)
    }

    public static func delete(_ name: String) throws {
        guard exists(name) else { throw PrefixError.notFound(name) }
        try FileManager.default.removeItem(at: prefixDir(name))
        try? FileManager.default.removeItem(at: snapshotRoot(name))
    }

    public static func list() -> [PrefixInfo] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: TeaPaths.prefixes,
            includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey]
        ) else { return [] }
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map {
                PrefixInfo(
                    name: $0.lastPathComponent,
                    url: $0,
                    createdAt: try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate
                )
            }
            .sorted { $0.name < $1.name }
    }

    /// 快照：clonefile 整个 prefix。命名 <时间戳>_<label>，天然按时间排序。
    @discardableResult
    public static func snapshot(_ name: String, label: String = "manual") throws -> SnapshotInfo {
        guard exists(name) else { throw PrefixError.notFound(name) }
        let stamp = timestamp()
        let safeLabel = label.replacingOccurrences(of: "/", with: "-")
        let root = snapshotRoot(name)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dest = root.appendingPathComponent("\(stamp)_\(safeLabel)", isDirectory: true)
        try clone(from: prefixDir(name), to: dest)
        return SnapshotInfo(name: dest.lastPathComponent, label: safeLabel, url: dest)
    }

    public static func snapshots(of name: String) -> [SnapshotInfo] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: snapshotRoot(name), includingPropertiesForKeys: nil) else {
            return []
        }
        return entries.map { url in
            let dirName = url.lastPathComponent
            let label = dirName.split(separator: "_", maxSplits: 1).count == 2
                ? String(dirName.split(separator: "_", maxSplits: 1)[1]) : dirName
            return SnapshotInfo(name: dirName, label: label, url: url)
        }.sorted { $0.name < $1.name }
    }

    /// 回滚：先把当前状态自动快照（pre-rollback），再用目标快照克隆回原位。
    /// 用户任何时候回滚都不会丢数据。
    public static func rollback(_ name: String, to snapshotName: String) throws {
        guard exists(name) else { throw PrefixError.notFound(name) }
        let source = snapshotRoot(name).appendingPathComponent(snapshotName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw PrefixError.snapshotNotFound(snapshotName)
        }
        try snapshot(name, label: "pre-rollback")
        try FileManager.default.removeItem(at: prefixDir(name))
        try clone(from: source, to: prefixDir(name))
    }

    public static func deleteSnapshot(_ name: String, snapshotName: String) throws {
        let target = snapshotRoot(name).appendingPathComponent(snapshotName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: target.path) else {
            throw PrefixError.snapshotNotFound(snapshotName)
        }
        try FileManager.default.removeItem(at: target)
    }

    // MARK: - 内部

    /// clonefile(2)：APFS 写时复制克隆，目录递归、保留元数据。
    static func clone(from src: URL, to dst: URL) throws {
        let result = clonefile(src.path, dst.path, 0)
        guard result == 0 else {
            throw PrefixError.cloneFailed(dst.path, errno)
        }
    }

    static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }
}
