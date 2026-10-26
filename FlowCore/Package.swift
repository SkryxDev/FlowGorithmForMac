// swift-tools-version: 6.2
// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import PackageDescription

let package = Package(
    name: "FlowCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "FlowCore", targets: ["FlowCore"]),
    ],
    targets: [
        .target(name: "FlowCore"),
        .testTarget(name: "FlowCoreTests", dependencies: ["FlowCore"]),
    ]
)
