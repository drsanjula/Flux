// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FluxLibrary",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
    ],
    products: [
        .library(name: "FluxLibrary", targets: ["FluxLibrary"]),
    ],
    targets: [
        .target(
            name: "FluxLibrary",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "FluxLibraryTests",
            dependencies: ["FluxLibrary"]
        ),
    ]
)
