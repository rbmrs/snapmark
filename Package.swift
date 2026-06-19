// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Printy",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "PrintyCore", targets: ["PrintyCore"]),
        .executable(name: "Printy", targets: ["Printy"])
    ],
    targets: [
        .target(
            name: "PrintyCore",
            path: "PrintyCore"
        ),
        .executableTarget(
            name: "Printy",
            dependencies: ["PrintyCore"],
            path: "Printy",
            exclude: ["Info.plist"]
        ),
        .executableTarget(
            name: "PrintyVerification",
            dependencies: ["PrintyCore"],
            path: "Verification"
        ),
        .testTarget(
            name: "PrintyCoreTests",
            dependencies: ["PrintyCore"],
            path: "PrintyCoreTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
