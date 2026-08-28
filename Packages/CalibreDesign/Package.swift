// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CalibreDesign",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "CalibreDesign", targets: ["CalibreDesign"])
    ],
    targets: [
        .target(
            name: "CalibreDesign",
            resources: [
                .copy("Fonts"),
                // Named file rather than the directory: a folder called
                // "Resources" at the root of a resource bundle collides with
                // the reserved bundle layout and codesign rejects it. `.copy`
                // rather than `.process` so the bytes stay the bytes — the same
                // tile ships to web and Android and being identical is the point.
                .copy("Resources/paper-grain.png"),
            ]
        ),
        .testTarget(
            name: "CalibreDesignTests",
            dependencies: ["CalibreDesign"]
        ),
    ]
)
