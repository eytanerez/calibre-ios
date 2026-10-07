// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RewatchKit",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "RewatchKit", targets: ["RewatchKit"])
    ],
    targets: [
        .target(name: "RewatchKit"),
        .testTarget(
            name: "RewatchKitTests",
            dependencies: ["RewatchKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
