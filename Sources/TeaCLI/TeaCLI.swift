import ArgumentParser
import TeaCore

@main
struct TeaCommand: ParsableCommand {
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

// MARK: - 子命令骨架（P0 占位，随 P1-P3 逐个实现）

struct Env: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "检测本机环境（芯片、内存、macOS、Rosetta、磁盘）")
    func run() throws {
        print("env: 尚未实现（P1）")
    }
}

struct Runtime: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "管理运行时组件（Wine、DXMT 等）")
    func run() throws {
        print("runtime: 尚未实现（P1）")
    }
}

struct Prefix: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "管理 Wine prefix（创建、删除、快照、回滚）")
    func run() throws {
        print("prefix: 尚未实现（P1）")
    }
}

struct Backend: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "管理图形后端（DXMT、D3DMetal）")
    func run() throws {
        print("backend: 尚未实现（P2）")
    }
}

struct Steam: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Windows Steam 安装与游戏库")
    func run() throws {
        print("steam: 尚未实现（P3）")
    }
}

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "启动游戏")
    func run() throws {
        print("run: 尚未实现（P3）")
    }
}

struct Report: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "生成诊断报告")
    func run() throws {
        print("report: 尚未实现（P5）")
    }
}
