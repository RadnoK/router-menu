// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZteMenu",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "zte-menu", targets: ["zte-menu"]),
    ],
    targets: [
        .target(name: "ZteMenu"),
        .executableTarget(name: "zte-menu", dependencies: ["ZteMenu"]),
        .testTarget(name: "ZteMenuTests", dependencies: ["ZteMenu"]),
    ]
)
