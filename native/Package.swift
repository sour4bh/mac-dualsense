// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CCControllerNative",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "CCControllerNative", targets: ["CCControllerNative"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0")
    ],
    targets: [
        .executableTarget(
            name: "CCControllerNative",
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

