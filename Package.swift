// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ProjectCanvas",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ProjectCanvas", targets: ["ProjectCanvas"])
    ],
    targets: [
        .executableTarget(name: "ProjectCanvas"),
        .testTarget(name: "ProjectCanvasTests", dependencies: ["ProjectCanvas"])
    ],
    swiftLanguageVersions: [.v5]
)
