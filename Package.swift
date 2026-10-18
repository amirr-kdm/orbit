// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ClaudeSchedule",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ClaudeSchedule", path: "Sources/ClaudeSchedule")
    ]
)
