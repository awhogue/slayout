// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Slayout",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Slayout", targets: ["Slayout"]),
        .library(name: "SlayoutCore", targets: ["SlayoutCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "Slayout",
            dependencies: ["SlayoutCore"],
            path: "Sources/Slayout"
        ),
        .target(
            name: "SlayoutCore",
            dependencies: [
                .product(name: "TOMLKit", package: "TOMLKit"),
            ],
            path: "Sources/SlayoutCore"
        ),
        .testTarget(
            name: "SlayoutCoreTests",
            dependencies: ["SlayoutCore"],
            path: "Tests/SlayoutCoreTests"
        ),
    ]
)
