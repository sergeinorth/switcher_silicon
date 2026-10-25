// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwitcherSilicon",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "Engine",
            path: "Sources/Engine"
        ),
        .target(
            name: "Platform",
            dependencies: ["Engine"],
            path: "Sources/Platform"
        ),
        .executableTarget(
            name: "SwitcherSilicon",
            dependencies: ["Engine", "Platform"],
            path: "Sources/App"
        ),
        .executableTarget(
            name: "Smoke",
            dependencies: ["Engine"],
            path: "Sources/Smoke"
        ),
        // XCTest / Testing require full Xcode; use `swift run Smoke` with CLT.
        .testTarget(
            name: "EngineTests",
            dependencies: ["Engine"],
            path: "Tests/EngineTests"
        ),
    ]
)
