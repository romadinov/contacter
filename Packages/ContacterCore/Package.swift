// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ContacterCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ContacterCore", targets: ["ContacterCore"]),
    ],
    targets: [
        .target(name: "ContacterCore"),
        .testTarget(name: "ContacterCoreTests", dependencies: ["ContacterCore"]),
    ]
)
