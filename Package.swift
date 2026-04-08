// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AutoCopy",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "AutoCopy", targets: ["AutoCopy"])
    ],
    targets: [
        .executableTarget(
            name: "AutoCopy",
            path: "AutoCopy",
            resources: [
                .copy("Resources/Assets.xcassets"),
                .copy("Resources/Info.plist")
            ]
        )
    ]
)
