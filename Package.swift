// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LongScreenshot",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "LongScreenshotCore",
            targets: ["LongScreenshotCore"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "LongScreenshotCore",
            dependencies: [],
            path: "LongScreenshot",
            exclude: [
                "Resources/Info.plist",
                "Resources/Assets.xcassets",
                "App/LongScreenshotApp.swift"
            ]
        ),
        .testTarget(
            name: "LongScreenshotTests",
            dependencies: ["LongScreenshotCore"],
            path: "LongScreenshotTests"
        ),
    ]
)
