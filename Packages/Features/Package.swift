// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Features",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Features", targets: ["Features"]),
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../APIClient"),
        .package(path: "../Persistence"),
        .package(path: "../Sync"),
        .package(path: "../DesignSystem"),
        .package(path: "../Natura"),
    ],
    targets: [
        .target(name: "Features", dependencies: ["Core", "APIClient", "Persistence", "Sync", "DesignSystem", "Natura"]),
    ]
)
