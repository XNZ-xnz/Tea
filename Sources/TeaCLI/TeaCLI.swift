import ArgumentParser
import Foundation
import TeaCore

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
    @Option(help: "runtime id") var runtime: String = "wine-devel-11.13"
    @Flag(help: "打印 wine 详细日志") var verbose: Bool = false
    @Argument(parsing: .captureForPassthrough, help: "程序与参数，如：cmd /c echo hi") var command: [String]

    func run() throws {
        guard let program = command.first else {
            throw ValidationError("缺少要运行的程序，例：tea run --prefix test cmd /c ver")
        }
        var env: [String: String] = [:]
        if verbose { env["WINEDEBUG"] = "warn+all,err+all" }

        let result = try WineRunner.run(
            runtimeId: runtime, prefix: prefix,
            program: program, arguments: Array(command.dropFirst()),
            environment: env
        )
        if !result.stdout.isEmpty { print(result.stdout, terminator: "") }
        if !result.stderr.isEmpty { FileHandle.standardError.write(Data(result.stderr.utf8)) }
        if let log = result.logFile { print("\n[日志] \(log.path)") }
        throw ExitCode(result.exitCode)
    }
}

// MARK: - 占位（P2/P3/P5 实现）

struct Backend: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "管理图形后端（DXMT、D3DMetal）")
    func run() throws { print("backend: 尚未实现（P2）") }
}

struct Steam: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Windows Steam 安装与游戏库")
    func run() throws { print("steam: 尚未实现（P3）") }
}

struct Report: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "生成诊断报告")
    func run() throws { print("report: 尚未实现（P5）") }
}
