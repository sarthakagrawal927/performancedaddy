// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PerformanceDaddy",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PerformanceCore", targets: ["PerformanceCore"]),
        .executable(name: "PerformanceDaddy", targets: ["PerformanceDaddy"]),
    ],
    targets: [
        .target(name: "NativeInspection"),
        .target(name: "PerformanceCore", dependencies: ["NativeInspection"]),
        .executableTarget(
            name: "PerformanceDaddy",
            dependencies: ["PerformanceCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "PerformanceCoreTests",
            dependencies: ["PerformanceCore"]
        ),
        .testTarget(name: "PerformanceDaddyTests", dependencies: ["PerformanceDaddy"]),
    ]
)
