// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SharedFoundation",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SharedFoundation", targets: ["SharedFoundation"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.3.0"),
    ],
    targets: [
        .target(
            name: "SharedFoundation",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
            ]
        ),
        .testTarget(
            name: "SharedFoundationTests",
            dependencies: ["SharedFoundation"]
        ),
    ]
)
