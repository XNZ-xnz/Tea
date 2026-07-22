import Foundation

/// runtime 组件清单：版本与 SHA256 钉死，仅 HTTPS。红线 3 的第一道闸。
public struct RuntimeManifest: Codable, Sendable {
    public let schemaVersion: Int
    public let components: [RuntimeComponent]

    public func component(id: String) -> RuntimeComponent? {
        components.first { $0.id == id }
    }
}

public struct RuntimeComponent: Codable, Sendable {
    /// 唯一标识，同时是安装目录名，如 "wine-devel-11.13"
    public let id: String
    /// 组件类别："wine" | "dxmt" | "gstreamer" …
    public let kind: String
    public let version: String
    /// 官方下载地址（必须 https）
    public let url: URL
    /// 压缩包的 SHA256（十六进制小写）
    public let sha256: String
    /// 压缩包字节数（进度显示与完整性预检）
    public let sizeBytes: Int64
    /// 事实来源备注（哪个官方仓库、何时核实）
    public let provenance: String
}

public enum ManifestStore {
    /// 内置 manifest：随代码更新，字段一律来自当日网络核实（见 provenance）。
    /// 后续可扩展为远端拉取 + 本地缓存，但内置版本永远是兜底。
    public static let builtin = RuntimeManifest(
        schemaVersion: 1,
        components: [
            RuntimeComponent(
                id: "wine-devel-11.13",
                kind: "wine",
                version: "11.13",
                url: URL(string: "https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.13/wine-devel-11.13-osx64.tar.xz")!,
                sha256: "214e2044d32870688c715c9edb1005a61beb7ba21ffe8e819da485163f754bd0", // 2026-07-23 首次下载实测钉入
                sizeBytes: 189_855_828,
                provenance: "github.com/Gcenx/macOS_Wine_builds release 11.13（2026-07-17 发布，2026-07-23 经 GitHub API 核实）"
            ),
            RuntimeComponent(
                id: "gptk-wine-3.0-2",
                kind: "wine",
                version: "3.0-2",
                url: URL(string: "https://github.com/Gcenx/game-porting-toolkit/releases/download/Game-Porting-Toolkit-3.0-2/game-porting-toolkit-3.0-2.tar.xz")!,
                sha256: "c16b3b40b9a34853fc1f4546d13d20d28bc06e0f2edcfcf425df2ef7f2ec4ba4", // Gcenx homebrew-wine tap cask 声称值，2026-07-23 下载实测复核通过
                sizeBytes: 0, // cask 未提供；首装后回填
                provenance: "github.com/Gcenx/game-porting-toolkit（Apple GPTK 官方 Read Me 点名的预构建环境；CrossOver 源码构建，D3DMetal 兼容底座）"
            ),
            RuntimeComponent(
                id: "dxmt-v0.80",
                kind: "dxmt",
                version: "0.80",
                url: URL(string: "https://github.com/3Shain/dxmt/releases/download/v0.80/dxmt-v0.80-builtin.tar.gz")!,
                sha256: "8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d", // 2026-07-23 首次下载实测钉入
                sizeBytes: 18_681_669,
                provenance: "github.com/3Shain/dxmt release v0.80（2026-04-23 发布，2026-07-23 经 GitHub API 核实；包内布局 x86_64-unix/x86_64-windows/i386-windows 已实物验证）"
            ),
        ]
    )
}
