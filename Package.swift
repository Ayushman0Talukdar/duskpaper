// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "duskpaper",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "duskpaper",
            path: "Sources/duskpaper",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
