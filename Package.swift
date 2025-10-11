// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CapacitorOfflineSpeechRecognition",
    platforms: [.iOS(.v14)],
    products: [
        .library(
            name: "CapacitorOfflineSpeechRecognition",
            targets: ["OfflineSpeechRecognitionPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "OfflineSpeechRecognitionPlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Sources/OfflineSpeechRecognitionPlugin"),
        .testTarget(
            name: "OfflineSpeechRecognitionPluginTests",
            dependencies: ["OfflineSpeechRecognitionPlugin"],
            path: "ios/Tests/OfflineSpeechRecognitionPluginTests")
    ]
)