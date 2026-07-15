// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZteMenu",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ZteMenu"),
        .testTarget(name: "ZteMenuTests", dependencies: ["ZteMenu"]),
    ]
)
