// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Kearch",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.0.0"),
        .package(url: "https://github.com/EmergeTools/Pow", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Kearch",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "Pow", package: "Pow")
            ],
            path: "Sources/Kearch"
        )
    ],
    swiftLanguageModes: [.v5]
)
