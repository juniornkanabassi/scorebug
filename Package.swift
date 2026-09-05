// swift-tools-version: 6.0
// Scorebug. Targets and dependencies are named by 00 Project State/ARCHITECTURE.md.
import PackageDescription

let package = Package(
    name: "Scorebug",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Scorebug", targets: ["Scorebug"]),
        .executable(name: "CoreChecks", targets: ["CoreChecks"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swhitty/FlyingFox.git", from: "0.20.0"),
    ],
    targets: [
        .target(name: "ScorebugCore", path: "Sources/ScorebugCore",
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "Scorebug",
            dependencies: ["ScorebugCore", .product(name: "FlyingFox", package: "FlyingFox")],
            path: "Sources/Scorebug",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(name: "CoreChecks", dependencies: ["ScorebugCore"], path: "Sources/CoreChecks",
                          swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
