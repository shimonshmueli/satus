// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AppLibrary",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Satus", targets: ["AppLibrary"])
    ],
    targets: [
        .executableTarget(
            name: "AppLibrary",
            path: "Sources/AppLibrary",
            resources: [],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/AppLibrary/Info.plist"
                ])
            ]
        )
    ]
)
