import Foundation
import Yams

/// 每游戏配方：recipes/<appid>.yaml。无配方的游戏走默认策略（PE 导入表猜后端）。
public struct Recipe: Codable, Sendable, Equatable {
    public let appid: String
    public let slug: String
    public let nameZh: String?
    public let engine: String?
    public let api: String?              // d3d11 / d3d12 / …
    public let backend: String?          // dxmt / d3dmetal / wined3d
    public let wine: String?             // runtime id 覆盖
    public let env: [String: String]?
    public let dllOverrides: String?     // 追加进 WINEDLLOVERRIDES
    public let launchArgs: [String]?
    public let notesZh: String?
    public let knownIssuesZh: [String]?

    enum CodingKeys: String, CodingKey {
        case appid, slug, engine, api, backend, wine, env
        case nameZh = "name_zh"
        case dllOverrides = "dll_overrides"
        case launchArgs = "launch_args"
        case notesZh = "notes_zh"
        case knownIssuesZh = "known_issues_zh"
    }
}

/// 一次启动的最终决策：recipe 有值用 recipe，缺省走默认。
public struct LaunchPlan: Sendable {
    public let backend: GraphicsBackend
    public let runtimeId: String
    public let environment: [String: String]
    public let source: String            // "recipe" / "default"
}

public struct RecipeStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func recipe(appid: String) -> Recipe? {
        let url = directory.appendingPathComponent("\(appid).yaml")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        do {
            return try YAMLDecoder().decode(Recipe.self, from: text)
        } catch {
            // 配方损坏视为无配方，但要在日志里留痕（不能悄悄吞掉）
            FileHandle.standardError.write(Data("recipe \(appid).yaml 解析失败：\(error)\n".utf8))
            return nil
        }
    }

    public func allRecipes() -> [Recipe] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "yaml" }
            .compactMap { url in
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return try? YAMLDecoder().decode(Recipe.self, from: text)
            }
            .sorted { $0.appid < $1.appid }
    }

    /// 组装一次启动的完整决策。
    /// exePath 用于无配方时的导入表探测（拿不到就按 v1 全局默认 d3dmetal）。
    public func launchPlan(appid: String, exePath: URL? = nil) -> LaunchPlan {
        if let r = recipe(appid: appid) {
            let backend = GraphicsBackend(rawValue: r.backend ?? "") ?? .d3dmetal
            var env = BackendManager.launchEnvironment(for: backend)
            for (k, v) in r.env ?? [:] { env[k] = v }
            if let extra = r.dllOverrides, !extra.isEmpty {
                let base = env["WINEDLLOVERRIDES"] ?? ""
                env["WINEDLLOVERRIDES"] = base.isEmpty ? extra : "\(base);\(extra)"
            }
            return LaunchPlan(
                backend: backend,
                runtimeId: r.wine ?? SteamManager.defaultRuntime,
                environment: env,
                source: "recipe"
            )
        }
        let backend = exePath.map { PEImports.guessBackend(of: $0) } ?? .d3dmetal
        return LaunchPlan(
            backend: backend,
            runtimeId: SteamManager.defaultRuntime,
            environment: BackendManager.launchEnvironment(for: backend),
            source: "default"
        )
    }
}
