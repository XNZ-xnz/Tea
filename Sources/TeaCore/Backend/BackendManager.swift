import Foundation

/// 图形后端。
public enum GraphicsBackend: String, Sendable, CaseIterable {
    case dxmt       // DX10/11 → Metal（默认）
    case d3dmetal   // DX12 → Metal（用户导入 GPTK 后可用）
    case wined3d    // wine 内置 GL 路径，兜底
}

public enum BackendError: Error, LocalizedError {
    case componentMissing(String)
    case variantExists(String)

    public var errorDescription: String? {
        switch self {
        case .componentMissing(let id): return "\(id) 未安装，先执行 tea runtime install \(id)。"
        case .variantExists(let id): return "变体 \(id) 已存在。"
        }
    }
}

/// DXMT 装配：不修改任何已装 runtime（只读原则），而是用 APFS clonefile
/// 克隆出 wine 变体，把 DXMT 文件按官方布局覆盖进克隆体。
///
/// 官方布局（DXMT wiki「Installation Guide for Geeks」，builtin 构建，2026-07-23 核实）：
/// - winemetal.so  → <wine>/lib/wine/x86_64-unix/
/// - winemetal.dll → <wine>/lib/wine/x86_64-windows/ 与 <prefix>/drive_c/windows/system32/
/// - d3d11.dll、dxgi.dll、d3d10core.dll → <wine>/lib/wine/x86_64-windows/
/// - i386 侧同理进 i386-windows/
/// - overrides 切勿设 native（builtin 版本就是替换内置）
public enum BackendManager {
    /// 变体 id 命名：<wineId>+<dxmtId>
    public static func variantId(wine wineId: String, dxmt dxmtId: String) -> String {
        "\(wineId)+\(dxmtId)"
    }

    /// 装配 wine+dxmt 变体 runtime。幂等：已存在直接返回 id。
    @discardableResult
    public static func assembleDXMTVariant(wine wineId: String, dxmt dxmtId: String) throws -> String {
        let id = variantId(wine: wineId, dxmt: dxmtId)
        let dest = RuntimeManager.installDir(for: id)
        if RuntimeManager.isInstalled(id) { return id }

        guard RuntimeManager.isInstalled(wineId) else { throw BackendError.componentMissing(wineId) }
        guard RuntimeManager.isInstalled(dxmtId) else { throw BackendError.componentMissing(dxmtId) }

        let fm = FileManager.default
        let wineSrc = RuntimeManager.installDir(for: wineId)
        let dxmtSrc = RuntimeManager.installDir(for: dxmtId)

        // 1. 秒级克隆整棵 wine 树
        try? fm.removeItem(at: dest)
        let rc = clonefile(wineSrc.path, dest.path, 0)
        guard rc == 0 else { throw PrefixError.cloneFailed(dest.path, errno) }

        // 2. 覆盖 DXMT 文件
        let mapping: [(from: String, to: String)] = [
            ("x86_64-unix/winemetal.so", "lib/wine/x86_64-unix/winemetal.so"),
            ("x86_64-windows/winemetal.dll", "lib/wine/x86_64-windows/winemetal.dll"),
            ("x86_64-windows/d3d11.dll", "lib/wine/x86_64-windows/d3d11.dll"),
            ("x86_64-windows/dxgi.dll", "lib/wine/x86_64-windows/dxgi.dll"),
            ("x86_64-windows/d3d10core.dll", "lib/wine/x86_64-windows/d3d10core.dll"),
            ("i386-windows/winemetal.dll", "lib/wine/i386-windows/winemetal.dll"),
            ("i386-windows/d3d11.dll", "lib/wine/i386-windows/d3d11.dll"),
            ("i386-windows/dxgi.dll", "lib/wine/i386-windows/dxgi.dll"),
            ("i386-windows/d3d10core.dll", "lib/wine/i386-windows/d3d10core.dll"),
        ]
        for entry in mapping {
            let src = dxmtSrc.appendingPathComponent(entry.from)
            guard fm.fileExists(atPath: src.path) else { continue } // nvapi 等可选文件跳过
            let dst = dest.appendingPathComponent(entry.to)
            try? fm.removeItem(at: dst)
            try fm.copyItem(at: src, to: dst)
        }

        // 3. 更新 marker（保留可追溯性）
        let marker = InstalledRuntime(
            id: id, kind: "wine+dxmt",
            version: "\(wineId) + \(dxmtId)",
            sha256: "assembled-locally",
            installedAt: Date()
        )
        try RuntimeManager.encoder().encode(marker)
            .write(to: dest.appendingPathComponent(RuntimeManager.markerName))
        return id
    }

    /// winemetal.dll 按官方要求同时放进 prefix 的 system32（64 位）与 syswow64（32 位）。
    public static func ensurePrefixSupport(prefix: String, dxmt dxmtId: String) throws {
        let fm = FileManager.default
        let dxmtSrc = RuntimeManager.installDir(for: dxmtId)
        let prefixRoot = PrefixManager.prefixDir(prefix)
        let pairs: [(String, String)] = [
            ("x86_64-windows/winemetal.dll", "drive_c/windows/system32/winemetal.dll"),
            ("i386-windows/winemetal.dll", "drive_c/windows/syswow64/winemetal.dll"),
        ]
        for (from, to) in pairs {
            let src = dxmtSrc.appendingPathComponent(from)
            let dst = prefixRoot.appendingPathComponent(to)
            guard fm.fileExists(atPath: src.path),
                  fm.fileExists(atPath: dst.deletingLastPathComponent().path) else { continue }
            try? fm.removeItem(at: dst)
            try fm.copyItem(at: src, to: dst)
        }
    }

    // MARK: - per-app DXMT（终极架构：Steam UI 与游戏共存，2026-07-23 定案）
    //
    // 背景：DXMT 全局注入会杀死 Steam 的 CEF 界面（交换链不兼容，cef_log 实证）。
    // 方案（DXMT wiki 的 native 安装模式 + wine 的 per-app overrides）：
    //   1. wine 树只添加 winemetal.so（不替换任何内置文件 → CEF 无感）
    //   2. DXMT 的 PE dll 放 prefix system32/syswow64（native 候选）
    //   3. 注册表 AppDefaults\<游戏exe>\DllOverrides = native → 只有游戏加载 DXMT

    /// 微变体：克隆 wine 树，仅添加 winemetal.so。幂等。
    @discardableResult
    public static func assembleWinemetalVariant(wine wineId: String, dxmt dxmtId: String) throws -> String {
        let id = "\(wineId)+winemetal"
        let dest = RuntimeManager.installDir(for: id)
        if RuntimeManager.isInstalled(id) { return id }
        guard RuntimeManager.isInstalled(wineId) else { throw BackendError.componentMissing(wineId) }
        guard RuntimeManager.isInstalled(dxmtId) else { throw BackendError.componentMissing(dxmtId) }

        let fm = FileManager.default
        try? fm.removeItem(at: dest)
        let rc = clonefile(RuntimeManager.installDir(for: wineId).path, dest.path, 0)
        guard rc == 0 else { throw PrefixError.cloneFailed(dest.path, errno) }

        let so = RuntimeManager.installDir(for: dxmtId).appendingPathComponent("x86_64-unix/winemetal.so")
        let soDst = dest.appendingPathComponent("lib/wine/x86_64-unix/winemetal.so")
        try? fm.removeItem(at: soDst)
        try fm.copyItem(at: so, to: soDst)

        let marker = InstalledRuntime(
            id: id, kind: "wine+winemetal",
            version: "\(wineId) + winemetal.so(\(dxmtId))",
            sha256: "assembled-locally", installedAt: Date()
        )
        try RuntimeManager.encoder().encode(marker)
            .write(to: dest.appendingPathComponent(RuntimeManager.markerName))
        return id
    }

    /// DXMT 的 PE 四件套放进 prefix（native 候选；不设全局 override 就不生效）。
    public static func placeDXMTNativeDLLs(prefix: String, dxmt dxmtId: String) throws {
        let fm = FileManager.default
        let src = RuntimeManager.installDir(for: dxmtId)
        let root = PrefixManager.prefixDir(prefix)
        let mapping: [(String, String)] = [
            ("x86_64-windows", "drive_c/windows/system32"),
            ("i386-windows", "drive_c/windows/syswow64"),
        ]
        for (from, to) in mapping {
            let srcDir = src.appendingPathComponent(from)
            let dstDir = root.appendingPathComponent(to)
            guard fm.fileExists(atPath: dstDir.path) else { continue }
            for name in ["d3d11.dll", "d3d10core.dll", "dxgi.dll", "winemetal.dll"] {
                let s = srcDir.appendingPathComponent(name)
                guard fm.fileExists(atPath: s.path) else { continue }
                let d = dstDir.appendingPathComponent(name)
                try? fm.removeItem(at: d)
                try fm.copyItem(at: s, to: d)
            }
        }
    }

    /// 给指定 exe 写 per-app DllOverrides（native 优先）。写注册表，持久生效。
    public static func setAppDXMTOverrides(prefix: String, runtimeId: String, exe: String) throws {
        let key = "HKCU\\Software\\Wine\\AppDefaults\\\(exe)\\DllOverrides"
        for dll in ["d3d11", "d3d10core", "dxgi"] {
            let result = try WineRunner.run(
                runtimeId: runtimeId, prefix: prefix,
                program: "reg",
                arguments: ["add", key, "/v", dll, "/d", "native,builtin", "/f"],
                logTag: "reg-appdefaults"
            )
            guard result.exitCode == 0 else {
                throw BackendError.componentMissing("注册表写入失败（\(dll)）：\(result.stderr)")
            }
        }
    }

    /// 装配 wine+D3DMetal 变体。前提：用户已导入 GPTK（红线：绝不下载）。
    ///
    /// 布局照抄官方 dmg（GPTK 4.0 beta 1 Read Me 的 ditto 方案，2026-07-23 实物核实）：
    /// - external/（D3DMetal.framework、libd3dshared.dylib）→ <wine>/lib/external/
    /// - wine/x86_64-unix/*.so → <wine>/lib/wine/x86_64-unix/
    ///   ⚠️ 这些 .so 全是指向 ../../external/libd3dshared.dylib 的符号链接，
    ///   必须保持 lib/external 与 lib/wine 平级，链接才能解析（踩坑实录见 PROGRESS.md）
    /// - wine/x86_64-windows/*.dll → <wine>/lib/wine/x86_64-windows/
    /// - GPTK 4 为纯 64 位（无 i386 文件）
    @discardableResult
    public static func assembleD3DMetalVariant(wine wineId: String) throws -> String {
        guard let gptk = GPTKImporter.importedInfo() else { throw GPTKError.notImported }
        let gptkTag = "d3dmetal-\(gptk.version.replacingOccurrences(of: " ", with: ""))"
        let id = variantId(wine: wineId, dxmt: gptkTag)
        let dest = RuntimeManager.installDir(for: id)
        if RuntimeManager.isInstalled(id) { return id }
        guard RuntimeManager.isInstalled(wineId) else { throw BackendError.componentMissing(wineId) }

        let fm = FileManager.default
        let wineSrc = RuntimeManager.installDir(for: wineId)
        let lib = GPTKImporter.importDir

        try? fm.removeItem(at: dest)
        let rc = clonefile(wineSrc.path, dest.path, 0)
        guard rc == 0 else { throw PrefixError.cloneFailed(dest.path, errno) }

        // external 整目录 → lib/external（symlink 解析基准）
        let externalDst = dest.appendingPathComponent("lib/external")
        try? fm.removeItem(at: externalDst)
        try fm.copyItem(at: lib.appendingPathComponent("external"), to: externalDst)

        // unix .so（symlink 原样保留）与 PE .dll 分别就位
        for (sub, dstSub) in [("wine/x86_64-unix", "lib/wine/x86_64-unix"),
                              ("wine/x86_64-windows", "lib/wine/x86_64-windows")] {
            let srcDir = lib.appendingPathComponent(sub)
            let dstDir = dest.appendingPathComponent(dstSub)
            for file in try fm.contentsOfDirectory(at: srcDir, includingPropertiesForKeys: nil) {
                let dst = dstDir.appendingPathComponent(file.lastPathComponent)
                try? fm.removeItem(at: dst)
                try fm.copyItem(at: file, to: dst)
            }
        }

        let marker = InstalledRuntime(
            id: id, kind: "wine+d3dmetal",
            version: "\(wineId) + GPTK \(gptk.version)",
            sha256: "assembled-locally",
            installedAt: Date()
        )
        try RuntimeManager.encoder().encode(marker)
            .write(to: dest.appendingPathComponent(RuntimeManager.markerName))
        return id
    }

    /// 后端对应的启动环境变量。
    ///
    /// D3DMetal 环境变量清单（GPTK 4.0 beta 1 dmg 内 Read Me 官方文档，2026-07-23 抄录）：
    /// - D3DM_SUPPORT_DXR：DXR 光追。M1/M2 默认 0，M3+ 默认 1 —— 尊重默认，不强设
    /// - ROSETTA_ADVERTISE_AVX：向游戏广告 AVX 指令集（macOS 15+），默认 0 —— recipes 按游戏开
    /// - D3DM_ENABLE_METALFX：DLSS→MetalFX（macOS 26+），默认 0 —— recipes 按游戏开
    /// - D3DM_MTL4：Metal 4 后端（macOS 27+）—— 实验项
    /// - D3DM_MAX_FPS：帧率上限
    public static func launchEnvironment(for backend: GraphicsBackend) -> [String: String] {
        switch backend {
        case .dxmt:
            // builtin 版：强制 builtin，防 prefix 内残留 native DLL 干扰
            return ["WINEDLLOVERRIDES": "d3d11,d3d10core,dxgi=b"]
        case .d3dmetal:
            return ["WINEDLLOVERRIDES": "d3d9,d3d10,d3d11,d3d12,d3d12core,dxgi=b"]
        case .wined3d:
            return [:]
        }
    }
}
