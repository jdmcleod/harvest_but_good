// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "HarvestTimer",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "HarvestTimerCore",
            path: "Sources/HarvestTimerCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "HarvestTimer",
            dependencies: ["HarvestTimerCore"],
            path: "Sources/HarvestTimer",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HarvestTimerCoreTests",
            dependencies: ["HarvestTimerCore"],
            path: "Tests/HarvestTimerCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
