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
            resources: [.copy("Fonts")]
        ),
        .testTarget(
            name: "CalibreDesignTests",
            dependencies: ["CalibreDesign"]
        ),
    ]
)
