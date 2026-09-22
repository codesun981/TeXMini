// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TeXMini",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TeXMini", targets: ["TeXMini"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "CSynctex",
            path: "Sources/CSynctex",
            publicHeadersPath: ".",
            cSettings: [
                .define("SYNCTEX_USE_LOCAL_HEADER", to: "1")
            ],
            linkerSettings: [
                .linkedLibrary("z")
            ]
        ),
        .executableTarget(
            name: "TeXMini",
            dependencies: ["CSynctex"],
            path: "Sources/TeXMini"
        )
    ]
)
