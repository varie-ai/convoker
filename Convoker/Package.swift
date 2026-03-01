// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Convoker",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
        .package(url: "https://github.com/krisk/fuse-swift", from: "1.4.0"),
    ],
    targets: [
        .executableTarget(
            name: "Convoker",
            dependencies: [
                "KeyboardShortcuts",
                .product(name: "Fuse", package: "fuse-swift"),
            ],
            path: "App"
        ),
    ]
)
