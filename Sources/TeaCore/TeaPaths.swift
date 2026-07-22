import Foundation

/// Tea 在磁盘上的固定位置。所有组件通过这里取路径，禁止散落硬编码。
public enum TeaPaths {
    /// ~/Library/Application Support/Tea
    public static var appSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tea", isDirectory: true)
    }

    /// 已安装的 runtime（Wine、DXMT 等），安装后视为只读不可变
    public static var runtimes: URL {
        appSupport.appendingPathComponent("runtimes", isDirectory: true)
    }

    /// Wine prefix 集合
    public static var prefixes: URL {
        appSupport.appendingPathComponent("prefixes", isDirectory: true)
    }

    /// 用户自备组件（GPTK/D3DMetal），绝不由 Tea 下载
    public static var userProvided: URL {
        appSupport.appendingPathComponent("user-provided", isDirectory: true)
    }

    /// 日志
    public static var logs: URL {
        appSupport.appendingPathComponent("logs", isDirectory: true)
    }

    /// 下载缓存（校验通过前的临时文件）
    public static var downloads: URL {
        appSupport.appendingPathComponent("downloads", isDirectory: true)
    }
}
