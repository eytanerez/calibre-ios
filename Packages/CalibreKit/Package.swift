// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CalibreKit",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "CalibreKit", targets: ["CalibreKit"])
    ],
    targets: [
        .target(name: "CalibreKit"),
        .testTarget(
            name: "CalibreKitTests",
            dependencies: ["CalibreKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
