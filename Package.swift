// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "HarvestTimer",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "HarvestTimerCore",
            path: "Sources/HarvestTimerCore"
        ),
        .executableTarget(
            name: "HarvestTimer",
            dependencies: ["HarvestTimerCore"],
            path: "Sources/HarvestTimer"
        ),
        .executableTarget(
            name: "HarvestTimerTestRunner",
            dependencies: ["HarvestTimerCore"],
            path: "Sources/HarvestTimerTestRunner"
        ),
    ]
)
