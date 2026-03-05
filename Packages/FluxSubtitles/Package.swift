// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FluxSubtitles",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
    ],
    products: [
        .library(name: "FluxSubtitles", targets: ["FluxSubtitles"]),
    ],
    targets: [
        .target(
            name: "FluxSubtitles",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
    ]
)
