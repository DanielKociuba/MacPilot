// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacPilot",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "MacPilot", path: "Sources/MacPilot"),
        .testTarget(name: "MacPilotTests", dependencies: ["MacPilot"])
    ]
)
