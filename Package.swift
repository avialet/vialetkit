// swift-tools-version: 6.0
// VialetKit : socle partage des apps Mac de vialet.app (mises a jour,
// theme, raccourci global, panneau flottant). Aucune dependance externe.
import PackageDescription

let package = Package(
    name: "VialetKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "VialetKit", targets: ["VialetKit"]),
    ],
    targets: [
        .target(name: "VialetKit"),
        // Harnais de tests : XCTest et Swift Testing ne sont pas livres avec
        // les Command Line Tools (voir docs/tests.md).
        .executableTarget(name: "vialetkit-check", dependencies: ["VialetKit"]),
    ]
)
