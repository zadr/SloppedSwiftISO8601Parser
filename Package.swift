// swift-tools-version: 6.2
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    // Required to declare the Span-holding ~Escapable lexer.
    .enableExperimentalFeature("Lifetimes"),
    .strictMemorySafety(),
]

let package = Package(
    name: "ISO8601",
    platforms: [.macOS(.v26), .iOS(.v26), .tvOS(.v26), .watchOS(.v26), .visionOS(.v26)],
    products: [
        .library(name: "ISO8601", targets: ["ISO8601"]),
    ],
    targets: [
        .target(name: "ISO8601", swiftSettings: swiftSettings),
        .testTarget(name: "ISO8601Tests", dependencies: ["ISO8601"], swiftSettings: swiftSettings),
    ]
)
