// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LongScreenshot",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "LongScreenshot",
            targets: ["LongScreenshot"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "LongScreenshot",
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
            dependencies: ["LongScreenshot"],
            path: "LongScreenshotTests"
        ),
    ]
)
