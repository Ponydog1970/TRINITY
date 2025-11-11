// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SimpleChatbot",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SimpleChatbot",
            targets: ["SimpleChatbot"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SimpleChatbot",
            dependencies: [],
            path: "SimpleChatbot"
        )
    ]
)
