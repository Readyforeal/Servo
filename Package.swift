// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Servo",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Servo", targets: ["Servo"])
    ],
    targets: [
        .executableTarget(name: "Servo"),
        .testTarget(name: "ServoTests", dependencies: ["Servo"])
    ],
    swiftLanguageModes: [.v5]
)
