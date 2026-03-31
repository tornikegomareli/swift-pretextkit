// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PretextKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "PretextKit", targets: ["PretextKit"]),
    ],
    targets: [
        .target(
            name: "PretextKit",
            path: "Sources/PretextKit"
        ),
        .testTarget(
            name: "PretextKitTests",
            dependencies: ["PretextKit"],
            path: "Tests/PretextKitTests"
        ),
    ]
)
