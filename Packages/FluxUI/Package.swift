// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FluxUI",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
    ],
    products: [
        .library(name: "FluxUI", targets: ["FluxUI"]),
    ],
    dependencies: [
        .package(path: "../FluxCore"),
        .package(path: "../FluxLibrary"),
        .package(path: "../FluxMetadata"),
        .package(path: "../FluxSubtitles"),
    ],
    targets: [
        .target(
            name: "FluxUI",
            dependencies: [
                "FluxCore",
                "FluxLibrary",
                "FluxMetadata",
                "FluxSubtitles",
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
    ]
)
