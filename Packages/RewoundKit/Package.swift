// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RewoundKit",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "RewoundKit", targets: ["RewoundKit"])
    ],
    targets: [
        .target(name: "RewoundKit"),
        .testTarget(
            name: "RewoundKitTests",
            dependencies: ["RewoundKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
