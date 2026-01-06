// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Satus",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Satus", targets: ["Satus"])
    ],
    targets: [
        .executableTarget(
            name: "Satus",
            path: "Sources/Satus",
            resources: [],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/Satus/Info.plist"
                ])
            ]
        )
    ]
)
