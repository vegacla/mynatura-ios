// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "APIClient",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "APIClient", targets: ["APIClient"]),
    ],
    targets: [
        .target(name: "APIClient"),
        .testTarget(name: "APIClientTests", dependencies: ["APIClient"]),
    ]
)
