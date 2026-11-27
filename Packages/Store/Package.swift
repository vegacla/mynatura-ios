// swift-tools-version:6.0
import PackageDescription

/// Store local (docs/local-first-migration.md §3): acciones que escriben directo en SwiftData e importación desde Natura.
let package = Package(
    name: "Store",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Store", targets: ["Store"]),
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../Persistence"),
        .package(path: "../Natura"),
    ],
    targets: [
        .target(name: "Store", dependencies: ["Core", "Persistence", "Natura"]),
    ]
)
