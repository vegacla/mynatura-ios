// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Natura",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Natura", targets: ["Natura"]),
    ],
    dependencies: [
        .package(path: "../Core"),
    ],
    targets: [
        .target(name: "Natura", dependencies: ["Core"]),
        .testTarget(name: "NaturaTests", dependencies: ["Natura"]),
    ]
)
