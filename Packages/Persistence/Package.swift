// swift-tools-version:6.0
import PackageDescription

// SwiftData: solo compila en plataformas Apple (no corre en el job de Linux; sus tests corren en macOS).
let package = Package(
    name: "Persistence",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Persistence", targets: ["Persistence"]),
    ],
    dependencies: [
        .package(path: "../Core"),
    ],
    targets: [
        .target(name: "Persistence", dependencies: ["Core"]),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence"]),
    ]
)
