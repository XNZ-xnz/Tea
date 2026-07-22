// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TeaCore",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(name: "TeaCore", targets: ["TeaCore"]),
        .executable(name: "tea", targets: ["TeaCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "TeaCore"
        ),
        .executableTarget(
            name: "TeaCLI",
            dependencies: [
                "TeaCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "TeaCoreTests",
            dependencies: ["TeaCore"]
        ),
    ]
)
