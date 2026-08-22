// swift-tools-version: 6.0
import PackageDescription

// El objetivo está partido en dos a propósito, y no por gusto arquitectónico: `CentinelaCore`
// no importa AppKit ni SwiftUI, así que su suite corre en un runner de CI sin sesión gráfica.
// Todo lo que puede estar mal —el parseo de la respuesta de Sentry, la normalización de la
// chispa, la lectura del llavero— vive ahí. `Centinela` es sólo la carcasa que dibuja.
let package = Package(
    name: "Centinela",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CentinelaCore",
            path: "Sources/CentinelaCore",
            // Modo 5 y no 6: la concurrencia estricta de Swift 6 obliga a anotar cosas que
            // acá no cruzan hilos, y el costo se paga en ruido, no en seguridad. Se sube a 6
            // cuando el proyecto tenga estado compartido de verdad.
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
        ),
    ]
)
