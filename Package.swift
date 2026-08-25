// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RouterMenu",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "router-menu", targets: ["router-menu"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.6"),
    ],
    targets: [
        .target(
            name: "RouterMenu",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")]
        ),
        .executableTarget(name: "router-menu", dependencies: ["RouterMenu"]),
        .testTarget(name: "RouterMenuTests", dependencies: ["RouterMenu"]),
    ]
)
