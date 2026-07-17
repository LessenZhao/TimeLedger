// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EvolutionCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "EvolutionCore", targets: ["EvolutionCore"]),
        .executable(name: "evolution-ledger-cli", targets: ["EvolutionLedgerCLI"])
    ],
    targets: [
        .target(name: "EvolutionCore"),
        .executableTarget(
            name: "EvolutionLedgerCLI",
            dependencies: ["EvolutionCore"]
        ),
        .testTarget(
            name: "EvolutionCoreTests",
            dependencies: ["EvolutionCore"],
            exclude: ["Fixtures"]
        )
    ]
)
