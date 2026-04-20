// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MacDualSense",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .executable(name: "MacDualSense", targets: ["MacDualSense"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0")
    ],
    targets: [
        .executableTarget(
            name: "MacDualSense",
            dependencies: [
                "Yams"
            ],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("GameController"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
            ]
        )
    ]
)
