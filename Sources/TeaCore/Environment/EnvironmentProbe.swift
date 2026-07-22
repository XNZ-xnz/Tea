import Foundation

/// 本机环境快照。字段与原始指令第 4 节的检测项一一对应。
public struct EnvironmentInfo: Sendable {
    public let chipName: String          // 如 "Apple M4"
    public let memoryBytes: UInt64
    public let macOSVersion: String      // 如 "27.0"
    public let macOSBuild: String        // 如 "26A5378n"
    public let rosettaInstalled: Bool
    public let diskFreeBytes: UInt64     // 用户主卷可用空间

    public var memoryGB: Int { Int(memoryBytes / 1_073_741_824) }
    public var diskFreeGB: Int { Int(diskFreeBytes / 1_073_741_824) }

    /// 硬件档位：base（标准 M 系）/ pro / max（Max 与 Ultra 同档）。
    /// 依据芯片名后缀判断；内存档位在兼容数据层另行约束。
    public var hardwareTier: HardwareTier {
        let name = chipName.lowercased()
        if name.contains("ultra") || name.contains("max") { return .max }
        if name.contains("pro") { return .pro }
        return .base
    }

    /// 8GB 机器按产品规则提示"不建议"。
    public var isMemoryDiscouraged: Bool { memoryGB < 12 }
}

public enum HardwareTier: String, Sendable {
    case base, pro, max
}

public enum EnvironmentProbe {
    /// 采集本机环境。全部走系统 API / sysctl，毫秒级完成。
    public static func probe() -> EnvironmentInfo {
        EnvironmentInfo(
            chipName: sysctlString("machdep.cpu.brand_string") ?? "未知芯片",
            memoryBytes: sysctlUInt64("hw.memsize") ?? 0,
            macOSVersion: {
                let v = ProcessInfo.processInfo.operatingSystemVersion
                return v.patchVersion == 0 ? "\(v.majorVersion).\(v.minorVersion)" : "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
            }(),
            macOSBuild: sysctlString("kern.osversion") ?? "unknown",
            rosettaInstalled: checkRosetta(),
            diskFreeBytes: diskFree()
        )
    }

    /// Rosetta 2 判定：oahd 守护进程注册文件存在即已安装。
    /// （用文件而非 pgrep：无需进程权限，且 oahd 空闲时也可能不在跑）
    static func checkRosetta() -> Bool {
        FileManager.default.fileExists(atPath: "/Library/Apple/usr/share/rosetta/rosetta")
    }

    static func diskFree() -> UInt64 {
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let capacity = values.volumeAvailableCapacityForImportantUsage else { return 0 }
        return UInt64(max(0, capacity))
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix(while: { $0 != 0 }), as: UTF8.self)
    }

    static func sysctlUInt64(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }
}
