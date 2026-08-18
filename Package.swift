// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "keynoter",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "keynoter", targets: ["Keynoter"])
    ],
    targets: [
        .executableTarget(
            name: "Keynoter",
            path: "Sources/Keynoter"
        ),
        .testTarget(
            name: "KeynoterTests",
            dependencies: ["Keynoter"],
            path: "Tests/KeynoterTests"
        )
    ]
)
