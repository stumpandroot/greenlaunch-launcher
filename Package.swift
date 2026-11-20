// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StumpRootApps",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "StumpRootApps", path: "Sources/StumpRootApps")
    ]
)
