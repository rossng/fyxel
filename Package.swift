// swift-tools-version: 6.0
import PackageDescription

let v5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Fyxel",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FyxelCore", targets: ["FyxelCore"]),
        .library(name: "FyxelMock", targets: ["FyxelMock"]),
        .executable(name: "Fyxel", targets: ["Fyxel"]),
        .executable(name: "fyxelctl", targets: ["fyxelctl"]),
    ],
    targets: [
        // Protocol, crypto, transport, models and operations. No UI.
        .target(name: "FyxelCore", swiftSettings: v5),
        // In-memory router with fictional data: demos, tests, screenshots.
        .target(name: "FyxelMock", dependencies: ["FyxelCore"], swiftSettings: v5),
        .executableTarget(name: "Fyxel", dependencies: ["FyxelCore", "FyxelMock"], swiftSettings: v5),
        .executableTarget(name: "fyxelctl", dependencies: ["FyxelCore", "FyxelMock"], swiftSettings: v5),
        .testTarget(name: "FyxelCoreTests", dependencies: ["FyxelCore", "FyxelMock"], swiftSettings: v5),
    ]
)
