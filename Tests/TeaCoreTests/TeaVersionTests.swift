import Testing
@testable import TeaCore

@Test func versionIsNonEmpty() {
    #expect(!TeaVersion.string.isEmpty)
}

@Test func pathsAreUnderAppSupport() {
    #expect(TeaPaths.runtimes.path.contains("Application Support/Tea"))
    #expect(TeaPaths.prefixes.path.contains("Application Support/Tea"))
    #expect(TeaPaths.userProvided.path.contains("Application Support/Tea"))
}
