// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Kearch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Kearch",
            path: "Sources/Kearch"
        )
    ],
    swiftLanguageModes: [.v5]
)
