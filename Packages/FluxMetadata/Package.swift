// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FluxMetadata",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
    ],
    products: [
        .library(name: "FluxMetadata", targets: ["FluxMetadata"]),
    ],
    dependencies: [
        .package(path: "../FluxLibrary"),
    ],
    targets: [
        .target(
            name: "FluxMetadata",
            dependencies: ["FluxLibrary"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "FluxMetadataTests",
            dependencies: ["FluxMetadata"]
        ),
    ]
)
