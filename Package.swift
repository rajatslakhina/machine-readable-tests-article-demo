// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TestTriage",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "TestTriage", targets: ["TestTriage"])
    ],
    targets: [
        .target(name: "TestTriage"),
        .testTarget(name: "TestTriageTests", dependencies: ["TestTriage"])
    ]
)
