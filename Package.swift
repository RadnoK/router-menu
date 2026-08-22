// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZteMenu",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "zte-menu", targets: ["zte-menu"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.6"),
    ],
    targets: [
        .target(
            name: "ZteMenu",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")]
        ),
        .executableTarget(name: "zte-menu", dependencies: ["ZteMenu"]),
        .testTarget(name: "ZteMenuTests", dependencies: ["ZteMenu"]),
    ]
)
