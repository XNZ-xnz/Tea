import Foundation
import Testing
@testable import TeaCore

/// 全套件共用一个 TEA_HOME 沙盒（进程级环境变量），各测试用独立 prefix 名避免踩踏。
private let sandbox: URL = {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("tea-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    setenv("TEA_HOME", dir.path, 1)
    return dir
}()

@Suite("PrefixManager（真实文件系统 + APFS clonefile）")
struct PrefixManagerTests {
    init() { _ = sandbox }

    @Test func createListDelete() throws {
        try PrefixManager.create("t-basic")
        #expect(PrefixManager.exists("t-basic"))
        #expect(PrefixManager.list().contains { $0.name == "t-basic" })

        #expect(throws: PrefixError.self) { try PrefixManager.create("t-basic") }

        try PrefixManager.delete("t-basic")
        #expect(!PrefixManager.exists("t-basic"))
    }

    @Test func snapshotAndRollbackRestoresContent() throws {
        try PrefixManager.create("t-snap")
        let file = PrefixManager.prefixDir("t-snap").appendingPathComponent("drive_c.txt")
        try "原始内容".write(to: file, atomically: true, encoding: .utf8)

        let snap = try PrefixManager.snapshot("t-snap", label: "clean")
        #expect(snap.label == "clean")

        try "被游戏搞坏的内容".write(to: file, atomically: true, encoding: .utf8)
        try PrefixManager.rollback("t-snap", to: snap.name)

        let restored = try String(contentsOf: file, encoding: .utf8)
        #expect(restored == "原始内容")

        // 回滚自动留了 pre-rollback 快照，坏状态也可找回
        #expect(PrefixManager.snapshots(of: "t-snap").contains { $0.label == "pre-rollback" })
    }

    @Test func rollbackToMissingSnapshotThrows() throws {
        try PrefixManager.create("t-missing")
        #expect(throws: PrefixError.self) {
            try PrefixManager.rollback("t-missing", to: "20000101-000000_nope")
        }
    }
}

@Suite("Downloader 安全闸")
struct DownloaderTests {
    @Test func rejectsNonHTTPS() async {
        await #expect(throws: DownloadError.insecureScheme("http")) {
            try await Downloader.download(
                URL(string: "http://example.com/x.tar.xz")!,
                to: FileManager.default.temporaryDirectory.appendingPathComponent("x"),
                expectedSHA256: "00"
            )
        }
    }

    @Test func sha256MatchesKnownVector() throws {
        // "abc" 的 SHA256 是公开测试向量
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("sha-vector-\(UUID().uuidString).txt")
        try Data("abc".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let hash = try Downloader.sha256Hex(of: file)
        #expect(hash == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}

@Suite("Manifest")
struct ManifestTests {
    @Test func builtinManifestIsSane() {
        let wine = ManifestStore.builtin.component(id: "wine-devel-11.13")
        #expect(wine != nil)
        #expect(wine?.url.scheme == "https")
        #expect(wine?.sha256.count == 64)
        #expect(wine?.provenance.isEmpty == false)
    }

    @Test func environmentProbeReturnsPlausibleValues() {
        let info = EnvironmentProbe.probe()
        #expect(!info.chipName.isEmpty)
        #expect(info.memoryGB >= 8)
        #expect(!info.macOSVersion.isEmpty)
    }
}
