import Foundation

public struct WineResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let logFile: URL?
}

public enum WineError: Error, LocalizedError {
    case runtimeNotInstalled(String)
    case prefixMissing(String)

    public var errorDescription: String? {
        switch self {
        case .runtimeNotInstalled(let id): return "runtime \(id) 未安装。先执行 tea runtime install \(id)。"
        case .prefixMissing(let n): return "prefix「\(n)」不存在。先执行 tea prefix create \(n)。"
        }
    }
}

/// wine 进程封装：环境组装、输出采集、日志落盘。
public enum WineRunner {
    /// 同步运行 wine 程序并等待退出。适用于 CLI 与短任务（wineboot、reg 等）。
    /// - program: Windows 侧命令（如 "wineboot"、"cmd"、exe 路径）
    /// - environment: 追加/覆盖的环境变量（DXMT/D3DMetal 的开关将从这里注入）
    public static func run(
        runtimeId: String,
        prefix: String,
        program: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        logTag: String? = nil
    ) throws -> WineResult {
        let wine = RuntimeManager.wineBinary(runtimeId: runtimeId)
        guard FileManager.default.fileExists(atPath: wine.path) else {
            throw WineError.runtimeNotInstalled(runtimeId)
        }
        guard PrefixManager.exists(prefix) else {
            throw WineError.prefixMissing(prefix)
        }

        let process = Process()
        process.executableURL = wine
        process.arguments = [program] + arguments

        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = PrefixManager.prefixDir(prefix).path
        // 默认压掉 fixme 噪音；诊断时由调用方显式覆盖 WINEDEBUG
        if env["WINEDEBUG"] == nil { env["WINEDEBUG"] = "fixme-all" }
        env.merge(environment) { _, new in new }
        // 无人值守红线：崩溃调试器 winedbg 会弹窗挂死进程树，一律禁用。
        // 与调用方的 overrides 合并（分号分隔），调用方显式设置 winedbg 时尊重调用方。
        let overrides = env["WINEDLLOVERRIDES"] ?? ""
        if !overrides.contains("winedbg") {
            env["WINEDLLOVERRIDES"] = overrides.isEmpty ? "winedbg.exe=d" : "\(overrides);winedbg.exe=d"
        }
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        // 先读后等：避免子进程输出灌满管道缓冲导致互相死锁
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let stdout = String(data: outData, encoding: .utf8) ?? ""
        let stderr = String(data: errData, encoding: .utf8) ?? ""

        let logFile = try? writeLog(
            tag: logTag ?? program.replacingOccurrences(of: "/", with: "_"),
            prefix: prefix, runtimeId: runtimeId,
            program: program, arguments: arguments,
            exitCode: process.terminationStatus, stdout: stdout, stderr: stderr
        )

        return WineResult(
            exitCode: process.terminationStatus,
            stdout: stdout, stderr: stderr, logFile: logFile
        )
    }

    /// 运行 wine 自带工具查版本（不需要 prefix 初始化，wine --version 不触碰 prefix）。
    public static func wineVersion(runtimeId: String) throws -> String {
        let wine = RuntimeManager.wineBinary(runtimeId: runtimeId)
        guard FileManager.default.fileExists(atPath: wine.path) else {
            throw WineError.runtimeNotInstalled(runtimeId)
        }
        let process = Process()
        process.executableURL = wine
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func writeLog(
        tag: String, prefix: String, runtimeId: String,
        program: String, arguments: [String],
        exitCode: Int32, stdout: String, stderr: String
    ) throws -> URL {
        try FileManager.default.createDirectory(at: TeaPaths.logs, withIntermediateDirectories: true)
        let stamp = PrefixManager.timestamp()
        let file = TeaPaths.logs.appendingPathComponent("\(stamp)_\(prefix)_\(tag).log")
        let content = """
        # Tea wine 日志
        time: \(stamp)
        runtime: \(runtimeId)
        prefix: \(prefix)
        command: \(program) \(arguments.joined(separator: " "))
        exit: \(exitCode)

        ## stdout
        \(stdout)

        ## stderr
        \(stderr)
        """
        try content.write(to: file, atomically: true, encoding: .utf8)
        return file
    }
}
