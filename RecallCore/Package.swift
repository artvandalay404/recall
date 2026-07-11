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
        .package(url: "https://github.com/groue/GRDB.swift.git", .upToNextMajor(from: "7.0.0")),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", .upToNextMajor(from: "0.9.0")),
    ],
    targets: [
        .target(
            name: "CZstd",
            path: "Sources/CZstd",
            publicHeadersPath: "include",
            cSettings: [
                .define("XXH_NAMESPACE", to: "ZSTD_"),
                .define("ZSTD_DISABLE_ASM", to: "1"),
            ]
        ),
        .target(
            name: "RecallCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                "CZstd",
            ]
        ),
        .testTarget(
            name: "RecallCoreTests",
            dependencies: ["RecallCore"]
        ),
    ]
)
