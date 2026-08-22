// swift-tools-version: 6.0
import PackageDescription

// The package is split in two on purpose, not out of architectural taste: `CentinelaCore`
// imports neither AppKit nor SwiftUI, so its suite runs on a CI runner with no graphics session.
// Everything that can be wrong in a way you cannot see — parsing Sentry's responses, the
// sparkline arithmetic, reading the Keychain — lives there. `Centinela` is only the shell that
// draws.
let package = Package(
    name: "Centinela",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CentinelaCore",
            path: "Sources/CentinelaCore",
            // Mode 5 and not 6: Swift 6's strict concurrency forces annotations on things that
            // do not cross threads here, and the cost is paid in noise, not in safety. It moves
            // to 6 when the project has real shared state.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Centinela",
            dependencies: ["CentinelaCore"],
            path: "Sources/Centinela",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CentinelaCoreTests",
            dependencies: ["CentinelaCore"],
            path: "Tests/CentinelaCoreTests",
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
