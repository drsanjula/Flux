// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FluxCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
    ],
    products: [
        .library(name: "FluxCore", targets: ["FluxCore"]),
    ],
    targets: [
        // C target: imports libmpv headers via pkg-config.
        // Requires PKG_CONFIG_PATH to include Dependencies/mpv/lib/pkgconfig.
        // Run Dependencies/Scripts/build-mpv-macos.sh first.
        .systemLibrary(
            name: "CLibMPV",
            pkgConfig: "mpv",
            providers: [
                .brew(["mpv"]),  // fallback: Homebrew mpv for development
            ]
        ),

        .target(
            name: "FluxCore",
            dependencies: ["CLibMPV"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),

        .testTarget(
            name: "FluxCoreTests",
            dependencies: ["FluxCore"]
        ),
    ]
)
