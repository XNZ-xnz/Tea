import Foundation

public struct SteamApp: Sendable, Equatable {
    public let appid: String
    public let name: String
    public let installdir: String
    public let buildid: String
    public let stateFlags: Int
    public let sizeOnDisk: Int64
    public let libraryPath: String   // 所属库的 Windows 路径

    /// StateFlags 含 4 = fully installed（Valve 语义）
    public var isFullyInstalled: Bool { stateFlags & 4 != 0 }
}

public enum SteamError: Error, LocalizedError {
    case notInstalled
    case installerFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .notInstalled: return "这个 prefix 里还没装 Windows Steam。先执行 tea steam install。"
        case .installerFailed(let code): return "Steam 安装器退出码 \(code)。查看日志定位原因。"
        }
    }
}

/// Windows Steam 的安装、库解析与启动链。
/// 红线 2：凭据永不接触——登录只发生在 Steam 自己的窗口，Tea 不读不存不自动化。
public enum SteamManager {
    /// Valve 官方安装器地址（红线 1：运行时获取，不随包分发）。
    /// 使用 Steam 官网「安装 Steam」按钮指向的 CDN 地址。
    public static let installerURL = URL(string: "https://cdn.fastly.steamstatic.com/client/installer/SteamSetup.exe")!

    /// 产品默认单一 steam prefix；底座 wine 见 defaultRuntime。
    public static let defaultPrefix = "steam"
    /// Steam 客户端底座（2026-07-23 深夜第三轮实测定案）：
    /// - gptk-wine（CX22，无 Vulkan）：steamwebhelper 循环崩溃 ✗
    /// - wine11+DXMT 变体：CEF 的 ANGLE 拿 DXMT d3d11 建窗口交换链失败
    ///   （SwapChain11 "Could not create additional swap chains" + EGL_BAD_ALLOC，cef_log 实证）✗
    /// - **wine11+winemetal 微变体** ✓：wine 树仅添加 winemetal.so，内置 d3d11/dxgi 原封不动
    ///   → CEF 走 wined3d/GL 老路径无感；游戏经 per-app overrides 加载 native DXMT
    public static var defaultRuntime: String {
        let variant = "wine-devel-11.13+winemetal"
        return RuntimeManager.isInstalled(variant) ? variant : "wine-devel-11.13"
    }

    public static func steamRoot(prefix: String) -> URL {
        PrefixManager.prefixDir(prefix)
            .appendingPathComponent("drive_c/Program Files (x86)/Steam", isDirectory: true)
    }

    public static func isInstalled(prefix: String) -> Bool {
        FileManager.default.fileExists(atPath: steamRoot(prefix: prefix).appendingPathComponent("steam.exe").path)
    }

    /// 下载官方安装器并静默安装（NSIS /S）。
    public static func install(
        prefix: String = defaultPrefix,
        runtimeId: String = defaultRuntime,
        progress: (@Sendable (String) -> Void)? = nil
    ) async throws {
        if !PrefixManager.exists(prefix) {
            try PrefixManager.create(prefix)
            progress?("已创建 prefix「\(prefix)」")
        }

        let setup = TeaPaths.downloads.appendingPathComponent("SteamSetup.exe")
        progress?("从 Valve 官方地址下载 Steam 安装器…")
        try FileManager.default.createDirectory(at: TeaPaths.downloads, withIntermediateDirectories: true)
        // 安装器由 Valve 滚动更新，无固定哈希可钉；HTTPS + 官方域名 + 每次新取
        let (temp, response) = try await URLSession.shared.download(from: installerURL)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw DownloadError.httpStatus(http.statusCode)
        }
        try? FileManager.default.removeItem(at: setup)
        try FileManager.default.moveItem(at: temp, to: setup)
        progress?("下载完成，开始静默安装（约 1-3 分钟）…")

        let result = try WineRunner.run(
            runtimeId: runtimeId, prefix: prefix,
            program: winePath(setup), arguments: ["/S"],
            environment: ["WINEDLLOVERRIDES": "mscoree=;mshtml=;winedbg.exe=d"],
            logTag: "steam-setup"
        )
        guard result.exitCode == 0 else { throw SteamError.installerFailed(result.exitCode) }
        guard isInstalled(prefix: prefix) else { throw SteamError.notInstalled }
        progress?("Windows Steam 安装完成")
    }

    /// 拉起 Steam。silent=true 时最小化托盘（游戏启动链用），false 打开完整窗口（逛商店）。
    /// 不等待退出——Steam 是长驻进程。
    public static func launch(
        prefix: String = defaultPrefix,
        runtimeId: String = defaultRuntime,
        silent: Bool,
        extraArgs: [String] = []
    ) throws {
        guard isInstalled(prefix: prefix) else { throw SteamError.notInstalled }
        let wine = RuntimeManager.wineBinary(runtimeId: runtimeId)
        let process = Process()
        process.executableURL = wine
        var args = ["C:\\Program Files (x86)\\Steam\\steam.exe"]
        // wine11+DXMT 底座上 CEF 走 GPU 加速（d3d11→DXMT→Metal / Vulkan→MoltenVK）。
        // 注意：`-cefdisablegpu` 软渲染在 macdrv 上反而渲染不出窗口内容（2026-07-23 实测），
        // 仅在无 Vulkan 底座时才考虑作为兜底。
        if silent { args.append("-silent") }
        args += extraArgs
        process.arguments = args

        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = PrefixManager.prefixDir(prefix).path
        env["WINEDEBUG"] = "fixme-all"
        env["WINEDLLOVERRIDES"] = "winedbg.exe=d"
        process.environment = env
        try process.run()
        // 不 wait：Steam 常驻。日志走 Steam 自己的 logs 目录。
    }

    /// 经运行中的 Steam 启动游戏（steam://rungameid）。Steam 未跑则由其自行拉起。
    public static func runGame(
        appid: String,
        prefix: String = defaultPrefix,
        runtimeId: String = defaultRuntime,
        environment: [String: String] = [:]
    ) throws {
        guard isInstalled(prefix: prefix) else { throw SteamError.notInstalled }
        let wine = RuntimeManager.wineBinary(runtimeId: runtimeId)
        let process = Process()
        process.executableURL = wine
        process.arguments = ["C:\\Program Files (x86)\\Steam\\steam.exe", "steam://rungameid/\(appid)"]

        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = PrefixManager.prefixDir(prefix).path
        env["WINEDEBUG"] = "fixme-all"
        env["WINEDLLOVERRIDES"] = "winedbg.exe=d"
        env.merge(environment) { _, new in new }
        process.environment = env
        try process.run()
    }

    // MARK: - 游戏库解析

    /// 解析 prefix 里全部 Steam 库的已装游戏。
    public static func installedApps(prefix: String = defaultPrefix) throws -> [SteamApp] {
        let vdf = steamRoot(prefix: prefix).appendingPathComponent("steamapps/libraryfolders.vdf")
        var libraryWinPaths = ["C:\\Program Files (x86)\\Steam"]
        if FileManager.default.fileExists(atPath: vdf.path) {
            let parsed = try KeyValues.parseFile(vdf)
            if let folders = parsed["libraryfolders"]?.dictValue {
                for (_, folder) in folders {
                    if let path = folder["path"]?.stringValue, !libraryWinPaths.contains(path) {
                        libraryWinPaths.append(path)
                    }
                }
            }
        }

        var apps: [SteamApp] = []
        for winPath in libraryWinPaths {
            guard let unixLib = unixPath(winPath, prefix: prefix) else { continue }
            let steamapps = unixLib.appendingPathComponent("steamapps")
            let entries = (try? FileManager.default.contentsOfDirectory(at: steamapps, includingPropertiesForKeys: nil)) ?? []
            for acf in entries where acf.lastPathComponent.hasPrefix("appmanifest_") && acf.pathExtension == "acf" {
                if let app = try? parseACF(acf, libraryPath: winPath) {
                    apps.append(app)
                }
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func parseACF(_ url: URL, libraryPath: String) throws -> SteamApp {
        let parsed = try KeyValues.parseFile(url)
        guard let state = parsed["AppState"] else {
            throw KeyValues.ParseError.unexpectedEnd
        }
        return SteamApp(
            appid: state["appid"]?.stringValue ?? "",
            name: state["name"]?.stringValue ?? "未知名称",
            installdir: state["installdir"]?.stringValue ?? "",
            buildid: state["buildid"]?.stringValue ?? "",
            stateFlags: Int(state["StateFlags"]?.stringValue ?? "0") ?? 0,
            sizeOnDisk: Int64(state["SizeOnDisk"]?.stringValue ?? "0") ?? 0,
            libraryPath: libraryPath
        )
    }

    // MARK: - 路径换算

    /// Windows 路径 → prefix 内 unix 路径（仅处理盘符路径；网络路径等返回 nil）
    static func unixPath(_ windowsPath: String, prefix: String) -> URL? {
        let normalized = windowsPath.replacingOccurrences(of: "\\\\", with: "\\")
        guard normalized.count >= 2, normalized[normalized.index(normalized.startIndex, offsetBy: 1)] == ":" else {
            return nil
        }
        let drive = normalized.prefix(1).lowercased()
        let rest = normalized.dropFirst(2)
            .replacingOccurrences(of: "\\", with: "/")
        let root = PrefixManager.prefixDir(prefix)
        if drive == "c" {
            return root.appendingPathComponent("drive_c").appendingPathComponent(rest)
        }
        // 其他盘符走 dosdevices 符号链接
        return root.appendingPathComponent("dosdevices/\(drive):").appendingPathComponent(rest)
    }

    /// unix 路径 → wine 可用的 Z: 盘路径
    static func winePath(_ url: URL) -> String {
        "Z:" + url.path.replacingOccurrences(of: "/", with: "\\")
    }
}
