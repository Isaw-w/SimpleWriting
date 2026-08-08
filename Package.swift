// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SimpleWriting",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SimpleWriting",
            path: "Sources"
        )
    ]
)
