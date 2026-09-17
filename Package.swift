// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "roto",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "roto", targets: ["Roto"]),
        .library(name: "RotoCore", targets: ["RotoCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.5.0"),
        // Test-only. CLT does not ship a complete Testing.framework.
        .package(url: "https://github.com/apple/swift-testing.git", from: "6.0.0"),
    ],
    targets: [
        .target(
            name: "RotoCore",
            dependencies: [
                .product(name: "TOMLKit", package: "TOMLKit"),
            ]
        ),
        .executableTarget(
            name: "Roto",
            dependencies: ["RotoCore"],
            resources: [
                .copy("Resources/emoji.json"),
                .copy("Resources/config.default.toml"),
            ]
        ),
        .testTarget(
            name: "RotoTests",
            dependencies: [
                "Roto",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
        .testTarget(
            name: "RotoCoreTests",
            dependencies: [
                "RotoCore",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ]
)
