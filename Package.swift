// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacBull",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MacBull",
            path: "Sources/MacBull"
        ),
        .testTarget(
            name: "MacBullTests",
            dependencies: ["MacBull"],
            path: "Tests/MacBullTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
