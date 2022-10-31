// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "FileRepo",
    platforms: [.iOS(.v13), .macOS(.v10_15)],
    products: [
        .library(
            name: "FileRepo",
            targets: ["FileRepo"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", branch: "main"),
        .package(url: "https://github.com/fltrWallet/HaByLo", branch: "main"),
    ],
    targets: [
        .target(
            name: "FileRepo",
            dependencies: [
                "HaByLo",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
            ]),
        .testTarget(
            name: "FileRepoTests",
            dependencies: ["FileRepo"]),
    ]
)
