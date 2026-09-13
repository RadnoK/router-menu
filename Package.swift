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
        // Built here purely so `swift build` and CI type-check the extension's
        // sources. The shipping `.appex` is assembled by xcodebuild, which is
        // the only toolchain that can produce an app extension bundle.
        .target(name: "RouterMenuWidget", dependencies: ["RouterMenu"]),
        .testTarget(name: "RouterMenuTests", dependencies: ["RouterMenu"]),
    ]
)
