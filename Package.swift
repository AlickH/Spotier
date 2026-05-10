// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SpotierCorePackage",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),
        .tvOS(.v17)
    ],
    products: [
        .library(name: "SpotierCore", targets: ["SpotierCore"])
    ],
    targets: [
        .target(
            name: "SpotierCore",
            path: "SpotierCore"
        )
    ]
)
