// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "loro",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
    ],
    targets: [
        .target(name: "LoroCore"),
        .target(name: "AudioEngineSafety"),
        .executableTarget(
            name: "loro",
            dependencies: [
                "LoroCore",
                "AudioEngineSafety",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "WhisperKit", package: "WhisperKit"),
            ]
        ),
        .testTarget(
            name: "loroTests",
            dependencies: ["LoroCore", "loro"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
