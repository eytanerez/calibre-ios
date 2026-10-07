// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RewatchDesign",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "RewatchDesign", targets: ["RewatchDesign"])
    ],
    targets: [
        .target(
            name: "RewatchDesign",
            resources: [
                // `.copy` rather than `.process` so the font bytes stay the
                // bytes. This list held one more entry until 2026-08-30 —
                // Resources/paper-grain.png — and it went out with the grain.
                .copy("Fonts")
            ]
        ),
        .testTarget(
            name: "RewatchDesignTests",
            dependencies: ["RewatchDesign"]
        ),
    ]
)
