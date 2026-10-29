// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MeuCleaner",
    defaultLocalization: "pt-BR",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MeuCleaner", targets: ["MeuCleaner"])
    ],
    targets: [
        .executableTarget(
            name: "MeuCleaner",
            path: "Sources/MeuCleaner",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit")
            ]
        ),
        .testTarget(
            name: "MeuCleanerTests",
            dependencies: ["MeuCleaner"],
            path: "Tests/MeuCleanerTests"
        )
    ]
)
