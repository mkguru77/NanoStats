// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NanoStats",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .executable(
            name: "NanoStats",
            targets: ["NanoStats"]
        )
    ],
    targets: [
        .executableTarget(
            name: "NanoStats",
            path: "Sources/NanoStats"
        )
    ]
)
