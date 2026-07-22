import Foundation

/// 轻量 PE 解析：只读导入表里的 DLL 名——用于无 recipe 游戏猜 DirectX 版本选后端。
public enum PEImports {
    public enum PEError: Error, LocalizedError {
        case notPE
        case malformed(String)

        public var errorDescription: String? {
            switch self {
            case .notPE: return "不是有效的 Windows 程序（PE 格式）"
            case .malformed(let d): return "PE 结构异常：\(d)"
            }
        }
    }

    /// 返回导入表里的 DLL 名（小写）。
    public static func importedDLLs(of exe: URL) throws -> [String] {
        let data = try Data(contentsOf: exe, options: .mappedIfSafe)
        guard data.count > 0x40, data[0] == 0x4D, data[1] == 0x5A else { throw PEError.notPE } // MZ

        let peOffset = Int(readU32(data, 0x3C))
        guard peOffset + 24 < data.count,
              data[peOffset] == 0x50, data[peOffset + 1] == 0x45,
              data[peOffset + 2] == 0, data[peOffset + 3] == 0 else { throw PEError.notPE } // PE\0\0

        let coff = peOffset + 4
        let numSections = Int(readU16(data, coff + 2))
        let optSize = Int(readU16(data, coff + 16))
        let opt = coff + 20
        guard opt + optSize <= data.count else { throw PEError.malformed("optional header 越界") }

        let magic = readU16(data, opt)
        let isPE32Plus = magic == 0x20B
        guard isPE32Plus || magic == 0x10B else { throw PEError.malformed("未知 optional header magic") }

        // DataDirectory[1] = Import Table
        let ddOffset = opt + (isPE32Plus ? 112 : 96)
        let importRVA = Int(readU32(data, ddOffset + 8))
        let importSize = Int(readU32(data, ddOffset + 12))
        if importRVA == 0 || importSize == 0 { return [] }

        // 节表：RVA → 文件偏移
        struct Section { let va: Int; let size: Int; let raw: Int }
        var sections: [Section] = []
        var sec = opt + optSize
        for _ in 0..<numSections {
            guard sec + 40 <= data.count else { throw PEError.malformed("节表越界") }
            sections.append(Section(
                va: Int(readU32(data, sec + 12)),
                size: max(Int(readU32(data, sec + 8)), Int(readU32(data, sec + 16))),
                raw: Int(readU32(data, sec + 20))
            ))
            sec += 40
        }
        func toOffset(_ rva: Int) -> Int? {
            for s in sections where rva >= s.va && rva < s.va + s.size {
                return s.raw + (rva - s.va)
            }
            return nil
        }

        guard var entry = toOffset(importRVA) else { throw PEError.malformed("导入表 RVA 无法映射") }
        var dlls: [String] = []
        while entry + 20 <= data.count {
            let nameRVA = Int(readU32(data, entry + 12))
            if nameRVA == 0 { break } // 全零结尾项
            if let nameOffset = toOffset(nameRVA), nameOffset < data.count {
                var end = nameOffset
                while end < data.count, data[end] != 0 { end += 1 }
                if let name = String(data: data[nameOffset..<end], encoding: .ascii) {
                    dlls.append(name.lowercased())
                }
            }
            entry += 20
        }
        return dlls
    }

    /// 按导入表猜图形后端。DX10/11 → DXMT（per-app 注入，金牌路径）；
    /// DX12 → d3dmetal（启动链待通，先如实标注）；其余 → dxmt 兜底。
    public static func guessBackend(of exe: URL) -> GraphicsBackend {
        guard let dlls = try? importedDLLs(of: exe) else { return .dxmt }
        if dlls.contains(where: { $0.hasPrefix("d3d12") }) { return .d3dmetal }
        return .dxmt
    }

    static func readU16(_ d: Data, _ o: Int) -> UInt16 {
        UInt16(d[o]) | (UInt16(d[o + 1]) << 8)
    }

    static func readU32(_ d: Data, _ o: Int) -> UInt32 {
        UInt32(d[o]) | (UInt32(d[o + 1]) << 8) | (UInt32(d[o + 2]) << 16) | (UInt32(d[o + 3]) << 24)
    }
}
