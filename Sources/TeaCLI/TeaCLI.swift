import AppKit
import ArgumentParser
import Foundation
import TeaCore

/// wine macdrv 创建的窗口不会自动到前台（Dock 有图标但看不到窗口，2026-07-23 实测）。
/// 用 CGWindowList 找到 wine 窗口的属主进程并激活——公开 API，无需辅助功能权限。
func activateWineWindows(retries: Int = 10) {
    for _ in 0..<retries {
        let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        let pids = Set(list.compactMap { w -> pid_t? in
            let owner = (w["kCGWindowOwnerName"] as? String ?? "").lowercased()
            guard owner.contains("wine") || owner.contains("steam") else { return nil }
            return w["kCGWindowOwnerPID"] as? pid_t
        })
        if !pids.isEmpty {
            for pid in pids {
                NSRunningApplication(processIdentifier: pid)?.activate()
            }
            return
        }
        Thread.sleep(forTimeInterval: 1)
    }
}

@main
struct TeaCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tea",
        abstract: "Tea — run Windows Steam games on macOS.",
        version: TeaVersion.string,
        subcommands: [
            Env.self,
            Runtime.self,
            Prefix.self,
            Backend.self,
            Steam.self,
            Run.self,
            Report.self,
        ]
    )
}

// MARK: - env

struct Env: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "检测本机环境（芯片、内存、macOS、Rosetta、磁盘）")

    func run() throws {
        let info = EnvironmentProbe.probe()
        print("""
        芯片        \(info.chipName)（档位：\(info.hardwareTier.rawValue)）
        内存        \(info.memoryGB) GB\(info.isMemoryDiscouraged ? "（不足 16GB，运行大型游戏不建议）" : "")
        macOS      \(info.macOSVersion)（\(info.macOSBuild)）
        Rosetta 2  \(info.rosettaInstalled ? "已安装" : "未安装 ← 运行 Windows 程序必需")
        磁盘可用    \(info.diskFreeGB) GB
        数据目录    \(TeaPaths.appSupport.path)
        """)
        if !info.rosettaInstalled {
            print("\n安装 Rosetta 2：softwareupdate --install-rosetta --agree-to-license")
            throw ExitCode(2)
        }
    }
}

// MARK: - runtime

struct Runtime: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "管理运行时组件（Wine、DXMT 等）",
        subcommands: [List.self, Install.self, Remove.self],
        defaultSubcommand: List.self
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "列出可用与已安装的 runtime")
        func run() throws {
            let installed = RuntimeManager.listInstalled()
            print("manifest 可用组件：")
            for c in ManifestStore.builtin.components {
                let mark = installed.contains { $0.id == c.id } ? "✓ 已安装" : "未安装"
                print("  [\(mark)] \(c.id)  (\(c.kind) \(c.version), \(c.sizeBytes / 1_048_576) MB)")
            }
            let orphans = installed.filter { i in !ManifestStore.builtin.components.contains { $0.id == i.id } }
            for o in orphans {
                print("  [✓ 已安装] \(o.id)  (\(o.kind) \(o.version)，已不在 manifest，保留可用)")
            }
        }
    }

    struct Install: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "install", abstract: "下载、校验并安装 runtime")
        @Argument(help: "组件 id，如 wine-devel-11.13") var id: String

        func run() async throws {
            try await RuntimeManager.install(id) { message in
                print("· \(message)")
            }
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "remove", abstract: "删除已安装的 runtime")
        @Argument var id: String
        func run() throws {
            try RuntimeManager.remove(id)
            print("已删除 \(id)")
        }
    }
}

// MARK: - prefix

struct Prefix: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "管理 Wine prefix（创建、删除、快照、回滚）",
        subcommands: [List.self, Create.self, Delete.self, Snapshot.self, Snapshots.self, Rollback.self],
        defaultSubcommand: List.self
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "列出全部 prefix")
        func run() throws {
            let all = PrefixManager.list()
            if all.isEmpty { print("（还没有 prefix，tea prefix create <名字> 创建）"); return }
            for p in all {
                let snaps = PrefixManager.snapshots(of: p.name).count
                print("\(p.name)  快照 \(snaps) 个  \(p.url.path)")
            }
        }
    }

    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "create", abstract: "创建 prefix")
        @Argument var name: String
        func run() throws {
            try PrefixManager.create(name)
            print("已创建 prefix「\(name)」（wine 环境将在首次运行时自动初始化）")
        }
    }

    struct Delete: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "delete", abstract: "删除 prefix 及其全部快照")
        @Argument var name: String
        func run() throws {
            try PrefixManager.delete(name)
            print("已删除 prefix「\(name)」")
        }
    }

    struct Snapshot: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "snapshot", abstract: "给 prefix 拍快照（APFS 克隆，秒级）")
        @Argument var name: String
        @Option(help: "快照备注") var label: String = "manual"
        func run() throws {
            let snap = try PrefixManager.snapshot(name, label: label)
            print("快照完成：\(snap.name)")
        }
    }

    struct Snapshots: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "snapshots", abstract: "列出 prefix 的快照")
        @Argument var name: String
        func run() throws {
            let snaps = PrefixManager.snapshots(of: name)
            if snaps.isEmpty { print("（无快照）"); return }
            for s in snaps { print(s.name) }
        }
    }

    struct Rollback: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "rollback", abstract: "回滚到某个快照（当前状态自动另存）")
        @Argument var name: String
        @Argument(help: "快照名（见 tea prefix snapshots）") var snapshot: String
        func run() throws {
            try PrefixManager.rollback(name, to: snapshot)
            print("已回滚「\(name)」到 \(snapshot)（回滚前状态存为 pre-rollback 快照）")
        }
    }
}

// MARK: - run

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "在 prefix 里运行 Windows 程序")

    @Option(help: "prefix 名") var prefix: String
    @Option(help: "runtime id（--backend dxmt 时自动选变体，可不填）") var runtime: String = "wine-devel-11.13"
    @Option(help: "图形后端：dxmt / wined3d") var backend: String = "wined3d"
    @Flag(help: "打印 wine 详细日志") var verbose: Bool = false
    @Argument(parsing: .captureForPassthrough, help: "程序与参数，如：cmd /c echo hi") var command: [String]

    func run() throws {
        guard let program = command.first else {
            throw ValidationError("缺少要运行的程序，例：tea run --prefix test cmd /c ver")
        }
        guard let gfx = GraphicsBackend(rawValue: backend) else {
            throw ValidationError("未知后端「\(backend)」，可选：\(GraphicsBackend.allCases.map(\.rawValue).joined(separator: " / "))")
        }

        var runtimeId = runtime
        var env = BackendManager.launchEnvironment(for: gfx)
        switch gfx {
        case .dxmt:
            runtimeId = try BackendManager.assembleDXMTVariant(wine: runtime, dxmt: "dxmt-v0.80")
            try BackendManager.ensurePrefixSupport(prefix: prefix, dxmt: "dxmt-v0.80")
        case .d3dmetal:
            // D3DMetal 走 gptk-wine 原装全家桶（自带 D3DMetal 3，实测 D3D12_OK）。
            // vanilla wine 与「GPTK4 库+GPTK3 wine」两条路实测均 c0000142，结论见 PROGRESS.md；
            // 用户导入的 GPTK 4 已登记，等兼容底座后由 assembleD3DMetalVariant 启用。
            runtimeId = runtime == "wine-devel-11.13" ? "gptk-wine-3.0-2" : runtime
            guard RuntimeManager.isInstalled(runtimeId) else {
                throw ValidationError("D3DMetal 需要 gptk-wine：tea runtime install gptk-wine-3.0-2")
            }
        case .wined3d:
            break
        }
        if verbose { env["WINEDEBUG"] = "warn+all,err+all" }

        let result = try WineRunner.run(
            runtimeId: runtimeId, prefix: prefix,
            program: program, arguments: Array(command.dropFirst()),
            environment: env
        )
        if !result.stdout.isEmpty { print(result.stdout, terminator: "") }
        if !result.stderr.isEmpty { FileHandle.standardError.write(Data(result.stderr.utf8)) }
        if let log = result.logFile { print("\n[日志] \(log.path)") }
        throw ExitCode(result.exitCode)
    }
}

// MARK: - backend

struct Backend: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "管理图形后端（DXMT、D3DMetal）",
        subcommands: [Assemble.self, Inject.self, ImportGPTK.self, Status.self],
        defaultSubcommand: Status.self
    )

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "status", abstract: "查看后端可用状态")
        func run() throws {
            print("DXMT      \(RuntimeManager.isInstalled("dxmt-v0.80") ? "✓ 已安装" : "未安装（tea runtime install dxmt-v0.80）")")
            if let g = GPTKImporter.importedInfo() {
                print("D3DMetal  ✓ 已导入（GPTK \(g.version)，来自 \(g.sourceDMGName)）")
            } else {
                print("D3DMetal  未导入（tea backend import-gptk <dmg路径>；dmg 从 Apple 官网自行下载）")
            }
        }
    }

    struct Assemble: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "assemble", abstract: "装配 wine+DXMT 变体 runtime（原版不动，秒级克隆）")
        @Option(help: "wine runtime id") var wine: String = "wine-devel-11.13"
        @Option(help: "dxmt runtime id") var dxmt: String = "dxmt-v0.80"
        func run() throws {
            let id = try BackendManager.assembleDXMTVariant(wine: wine, dxmt: dxmt)
            print("变体就绪：\(id)")
        }
    }

    struct Inject: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "inject",
            abstract: "给指定 exe 精准注入 DXMT（per-app，prefix 内其他程序不受影响）"
        )
        @Option(help: "prefix 名") var prefix: String
        @Option(help: "目标 exe 名，如 P5R.exe") var exe: String

        func run() throws {
            let variant = try BackendManager.assembleWinemetalVariant(wine: "wine-devel-11.13", dxmt: "dxmt-v0.80")
            try BackendManager.placeDXMTNativeDLLs(prefix: prefix, dxmt: "dxmt-v0.80")
            try BackendManager.setAppDXMTOverrides(prefix: prefix, runtimeId: variant, exe: exe)
            print("已注入：\(exe) 在 prefix「\(prefix)」将使用 DXMT（runtime \(variant)）")
        }
    }

    struct ImportGPTK: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "import-gptk",
            abstract: "从用户自备的 GPTK dmg 导入 D3DMetal（Tea 绝不下载或分发它）"
        )
        @Argument(help: "GPTK dmg 路径（外层或内层 Evaluation dmg 均可）") var dmg: String

        func run() throws {
            let url = URL(fileURLWithPath: (dmg as NSString).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ValidationError("文件不存在：\(url.path)")
            }
            let info = try GPTKImporter.importDMG(at: url) { print("· \($0)") }
            print("D3DMetal 就绪（GPTK \(info.version)）。用 --backend d3dmetal 启动 DX12 游戏。")
        }
    }
}

struct Steam: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Windows Steam 安装与游戏库",
        subcommands: [Install.self, Launch.self, Apps.self, Game.self],
        defaultSubcommand: Apps.self
    )

    struct Install: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "install", abstract: "下载官方安装器并静默安装 Windows Steam")
        @Option(help: "prefix 名") var prefix: String = SteamManager.defaultPrefix
        @Option(help: "runtime id") var runtime: String = SteamManager.defaultRuntime

        func run() async throws {
            guard RuntimeManager.isInstalled(runtime) else {
                throw ValidationError("先安装底座：tea runtime install \(runtime)")
            }
            try await SteamManager.install(prefix: prefix, runtimeId: runtime) { print("· \($0)") }
            print("完成。下一步 tea steam launch 打开 Steam 登录窗口（登录只发生在 Steam 自己的窗口里）。")
        }
    }

    struct Launch: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "launch", abstract: "打开 Steam 窗口（登录、逛商店、下载游戏）")
        @Option(help: "prefix 名") var prefix: String = SteamManager.defaultPrefix
        @Option(help: "runtime id") var runtime: String = SteamManager.defaultRuntime
        @Flag(help: "静默启动（最小化到托盘）") var silent: Bool = false

        func run() throws {
            try SteamManager.launch(prefix: prefix, runtimeId: runtime, silent: silent)
            print("Steam 正在启动（首次启动会自更新，需要几分钟）。")
            if !silent {
                print("等待窗口出现并带到前台…")
                Thread.sleep(forTimeInterval: 8)
                activateWineWindows()
            }
        }
    }

    struct Apps: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "apps", abstract: "列出已安装的 Steam 游戏")
        @Option(help: "prefix 名") var prefix: String = SteamManager.defaultPrefix

        func run() throws {
            let apps = try SteamManager.installedApps(prefix: prefix)
            if apps.isEmpty {
                print("（游戏库为空——在 Steam 窗口里安装游戏后再来）")
                return
            }
            for app in apps {
                let size = String(format: "%.1f GB", Double(app.sizeOnDisk) / 1_073_741_824)
                let state = app.isFullyInstalled ? "✓" : "…"
                print("[\(state)] \(app.appid)  \(app.name)  (\(size), build \(app.buildid))")
            }
        }
    }

    struct Game: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "game", abstract: "经 Steam 启动游戏（steam://rungameid）")
        @Option(help: "prefix 名") var prefix: String = SteamManager.defaultPrefix
        @Argument(help: "Steam appid，如 1687950") var appid: String

        func run() throws {
            let store = RecipeStore(directory: URL(fileURLWithPath: "recipes"))
            let plan = store.launchPlan(appid: appid)
            print("启动方案（\(plan.source)）：后端 \(plan.backend.rawValue)，runtime \(plan.runtimeId)")

            if plan.backend == .dxmt && !plan.runtimeId.contains("xom") {
                // per-app DXMT 注入仅用于非 XoM 底座（XoM 的 builtin 本身就是 DXMT）。
                // 注意：DXMT 官方产物均带 wine builtin 标记，native 注入实测无效（见 PROGRESS.md），
                // 此路径保留等 normal 构建出现；当前 recipes 应指定 wine: winecx-xom-5.4.2。
                let variant = try BackendManager.assembleWinemetalVariant(wine: "wine-devel-11.13", dxmt: "dxmt-v0.80")
                try BackendManager.placeDXMTNativeDLLs(prefix: prefix, dxmt: "dxmt-v0.80")
                if let exe = plan.exe {
                    try BackendManager.setAppDXMTOverrides(prefix: prefix, runtimeId: variant, exe: exe)
                    print("DXMT 已按 exe 精准注入：\(exe)")
                }
            }

            try SteamManager.runGame(appid: appid, prefix: prefix, runtimeId: plan.runtimeId, environment: plan.environment)
            print("已请求 Steam 启动 appid \(appid)。")
        }
    }
}

struct Report: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "生成诊断报告")
    func run() throws { print("report: 尚未实现（P5）") }
}
