// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RecallCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "RecallCore",
            targets: ["RecallCore"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", .upToNextMajor(from: "7.0.0"))
    ],
    targets: [
        .target(
            name: "RecallCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "RecallCoreTests",
            dependencies: ["RecallCore"]
        ),
    ]
)
