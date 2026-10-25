// swift-tools-version: 6.0
// Scorebug. Targets and dependencies are named by 00 Project State/ARCHITECTURE.md.
import PackageDescription

let package = Package(
    name: "Scorebug",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Scorebug", targets: ["Scorebug"]),
        .executable(name: "CoreChecks", targets: ["CoreChecks"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swhitty/FlyingFox.git", from: "0.20.0"),
        // Self-updating, the same Sparkle release as Talk & Read and Video Prompter.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .target(name: "ScorebugCore", path: "Sources/ScorebugCore",
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "Scorebug",
            dependencies: ["ScorebugCore", .product(name: "FlyingFox", package: "FlyingFox"),
                           .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Scorebug",
            swiftSettings: [.swiftLanguageMode(.v5)],
            // build.sh embeds Sparkle.framework in Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .executableTarget(name: "CoreChecks", dependencies: ["ScorebugCore"], path: "Sources/CoreChecks",
                          swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
