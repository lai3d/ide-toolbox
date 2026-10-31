// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "IDEToolbox",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ToolboxCore"),
        .executableTarget(name: "IDEToolbox", dependencies: ["ToolboxCore"]),
        .testTarget(name: "ToolboxCoreTests", dependencies: ["ToolboxCore"]),
    ]
)
