// swift-tools-version: 6.0
import Foundation
import PackageDescription

/// `make fff` (or scripts/bundle.sh) builds the fff bridge here before SwiftPM links it.
let fffLibraryDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("native/fff-bridge/target/release")
    .path

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
        // App search runs on fff, a Rust library; see native/fff-bridge.
        .systemLibrary(name: "CFFFBridge", path: "Sources/CFFFBridge"),
        .executableTarget(
            name: "Roto",
            dependencies: ["RotoCore", "CFFFBridge"],
            resources: [
                .copy("Resources/emoji.json"),
                .copy("Resources/config.default.toml"),
            ],
            linkerSettings: [
                .unsafeFlags(["-L", fffLibraryDirectory]),
                // What the Rust static library needs from the system.
                .linkedFramework("CoreServices"),
                .linkedFramework("Security"),
                .linkedLibrary("iconv"),
                .linkedLibrary("z"),
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
