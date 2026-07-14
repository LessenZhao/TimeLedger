// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EvolutionCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "EvolutionCore", targets: ["EvolutionCore"])
    ],
    targets: [
        .target(name: "EvolutionCore"),
        .testTarget(
            name: "EvolutionCoreTests",
            dependencies: ["EvolutionCore"]
        )
    ]
)
