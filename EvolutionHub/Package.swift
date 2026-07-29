// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EvolutionHub",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "EvolutionHubCore", targets: ["EvolutionHubCore"]),
        .executable(name: "EvolutionHub", targets: ["EvolutionHub"])
    ],
    dependencies: [
        .package(path: "../Packages/EvolutionCore")
    ],
    targets: [
        .target(
            name: "EvolutionHubCore",
            dependencies: [
                .product(name: "EvolutionCore", package: "EvolutionCore")
            ]
        ),
        .executableTarget(
            name: "EvolutionHub",
            dependencies: [
                "EvolutionHubCore",
                .product(name: "EvolutionCore", package: "EvolutionCore")
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "EvolutionHubCoreTests",
            dependencies: [
                "EvolutionHubCore",
                .product(name: "EvolutionCore", package: "EvolutionCore")
            ],
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
