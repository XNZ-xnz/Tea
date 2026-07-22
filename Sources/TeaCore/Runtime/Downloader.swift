import Foundation
import CryptoKit

/// 安全敏感区（红线 3）：仅 HTTPS、SHA256 强制校验、失败即中止并清理。
public enum DownloadError: Error, LocalizedError, Equatable {
    case insecureScheme(String)
    case httpStatus(Int)
    case checksumMismatch(expected: String, actual: String)
    case fileMissing

    public var errorDescription: String? {
        switch self {
        case .insecureScheme(let s):
            return "拒绝非 HTTPS 下载（\(s)://）。runtime 只允许走加密通道。"
        case .httpStatus(let code):
            return "下载失败：服务器返回 \(code)。"
        case .checksumMismatch(let expected, let actual):
            return "文件校验失败，已丢弃。期望 SHA256 \(expected.prefix(12))…，实际 \(actual.prefix(12))…。可能是下载损坏或来源被篡改，请重试；若反复失败请到项目页反馈。"
        case .fileMissing:
            return "下载完成但文件不存在。"
        }
    }
}

public enum Downloader {
    /// 下载到目标路径并强制校验 SHA256。任何一步失败都抛错并清理残file。
    /// - progress: 已收字节 / 总字节（总数未知时为 -1）
    public static func download(
        _ url: URL,
        to destination: URL,
        expectedSHA256: String,
        progress: (@Sendable (Int64, Int64) -> Void)? = nil
    ) async throws {
        guard url.scheme?.lowercased() == "https" else {
            throw DownloadError.insecureScheme(url.scheme ?? "nil")
        }

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let (tempURL, response) = try await URLSession.shared.download(from: url, delegate: nil)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw DownloadError.httpStatus(http.statusCode)
        }

        let actual = try sha256Hex(of: tempURL)
        guard actual == expectedSHA256.lowercased() else {
            throw DownloadError.checksumMismatch(expected: expectedSHA256.lowercased(), actual: actual)
        }

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
        progress?(1, 1)
    }

    /// 流式计算文件 SHA256（64KB 分块，190MB 的 wine 包内存占用恒定）。
    public static func sha256Hex(of fileURL: URL) throws -> String {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            throw DownloadError.fileMissing
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: 65536)
            guard !chunk.isEmpty else { return false }
            hasher.update(data: chunk)
            return true
        }) {}

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
