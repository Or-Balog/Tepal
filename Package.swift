// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Tepal",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "Tepal", targets: ["TepalApp"])],
    targets: [
        .target(name: "TepalCore"),
        .target(name: "TepalMac", dependencies: ["TepalCore"], resources: [.process("Resources")]),
        .executableTarget(name: "TepalApp", dependencies: ["TepalCore", "TepalMac"], resources: [.process("Resources")]),
        .testTarget(name: "TepalCoreTests", dependencies: ["TepalCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "TepalMacTests", dependencies: ["TepalCore", "TepalMac"]),
        .testTarget(
            name: "TepalAppTests",
            dependencies: ["TepalCore", "TepalMac", "TepalApp"]
        ),
    ]
)
