// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Snapmark",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "SnapmarkCore", targets: ["SnapmarkCore"]),
        .executable(name: "Snapmark", targets: ["Snapmark"])
    ],
    targets: [
        .target(
            name: "SnapmarkCore",
            path: "SnapmarkCore"
        ),
        .executableTarget(
            name: "Snapmark",
            dependencies: ["SnapmarkCore"],
            path: "Snapmark",
            exclude: ["Info.plist", "Resources"]
        ),
        .executableTarget(
            name: "SnapmarkVerification",
            dependencies: ["SnapmarkCore"],
            path: "SnapmarkVerification"
        ),
        .testTarget(
            name: "SnapmarkCoreTests",
            dependencies: ["SnapmarkCore"],
            path: "SnapmarkCoreTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
