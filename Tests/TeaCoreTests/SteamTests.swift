import Foundation
import Testing
@testable import TeaCore

@Suite("KeyValues（VDF/ACF）解析")
struct KeyValuesTests {
    @Test func parsesLibraryFoldersFixture() throws {
        let vdf = """
        // 注释也要能吞掉
        "libraryfolders"
        {
            "0"
            {
                "path"		"C:\\\\Program Files (x86)\\\\Steam"
                "label"		""
                "apps"
                {
                    "1687950"		"43681237928"
                }
            }
            "1"
            {
                "path"		"D:\\\\SteamLibrary"
            }
        }
        """
        let parsed = try KeyValues.parse(vdf)
        let folders = try #require(parsed["libraryfolders"]?.dictValue)
        #expect(folders.count == 2)
        #expect(parsed["libraryfolders"]?["0"]?["path"]?.stringValue == "C:\\Program Files (x86)\\Steam")
        #expect(parsed["libraryfolders"]?["1"]?["path"]?.stringValue == "D:\\SteamLibrary")
        #expect(parsed["libraryfolders"]?["0"]?["apps"]?["1687950"]?.stringValue == "43681237928")
    }

    @Test func parsesAppManifestFixtureCaseInsensitive() throws {
        let acf = """
        "AppState"
        {
            "appid"		"1687950"
            "name"		"Persona 5 Royal"
            "StateFlags"		"4"
            "installdir"		"P5R"
            "buildid"		"10476728"
            "SizeOnDisk"		"43681237928"
        }
        """
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("appmanifest_test.acf")
        try acf.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let app = try SteamManager.parseACF(tmp, libraryPath: "C:\\Program Files (x86)\\Steam")
        #expect(app.appid == "1687950")
        #expect(app.name == "Persona 5 Royal")
        #expect(app.isFullyInstalled)
        #expect(app.sizeOnDisk == 43_681_237_928)
        // 大小写不敏感查询
        let parsed = try KeyValues.parse(acf)
        #expect(parsed["appstate"]?["stateflags"]?.stringValue == "4")
    }

    @Test func malformedInputThrows() {
        #expect(throws: KeyValues.ParseError.self) {
            try KeyValues.parse("\"a\" { \"b\" ")
        }
    }
}

@Suite("PE 导入表")
struct PEImportsTests {
    /// 用仓库里的 d3d11 冒烟 exe 当 fixture（mingw 编译，导入表必含 d3d11.dll）
    @Test func smokeExeImportsD3D11() throws {
        let exe = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/TeaCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // 仓库根
            .appendingPathComponent("tools/d3d11-smoke/d3d11_smoke.exe")
        guard FileManager.default.fileExists(atPath: exe.path) else {
            // exe 是本机编译产物不入库；没有就跳过（CI 上属正常）
            return
        }
        let dlls = try PEImports.importedDLLs(of: exe)
        #expect(dlls.contains("d3d11.dll"))
        #expect(dlls.contains("kernel32.dll"))
    }

    @Test func nonPEThrows() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("not-pe-\(UUID().uuidString).exe")
        try Data("这不是PE文件".utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        #expect(throws: PEImports.PEError.self) {
            _ = try PEImports.importedDLLs(of: tmp)
        }
    }

    @Test func windowsPathConversion() {
        let unix = SteamManager.unixPath("C:\\Program Files (x86)\\Steam", prefix: "whatever")
        #expect(unix?.path.hasSuffix("prefixes/whatever/drive_c/Program Files (x86)/Steam") == true)
        #expect(SteamManager.unixPath("not-a-path", prefix: "x") == nil)
    }
}
