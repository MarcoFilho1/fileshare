// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "FileShare",
    platforms: [.macOS(.v14)],
    targets: [
        // Lógica testável: protocolo e área de transferência.
        .target(name: "FileShareCore"),
        // App de barra de menu: conexão com o tablet e interface.
        .executableTarget(name: "FileShare", dependencies: ["FileShareCore"]),
        .testTarget(name: "FileShareCoreTests", dependencies: ["FileShareCore"]),
    ],
    swiftLanguageModes: [.v5]
)
