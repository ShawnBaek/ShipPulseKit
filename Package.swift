// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShipPulseKit",
    platforms: [
        // iOS 27+ only: uses MetricKit's Swift MetricManager and StateReporting.
        .iOS("27.0"),
        .macOS("27.0"),
        .watchOS("27.0"),
        .visionOS("27.0"),
    ],
    products: [
        // Add this to your app.
        .library(name: "ShipPulseKit", targets: ["ShipPulseKit"]),
        // Record schema, summaries, histogram math and sampling, shared with the ShipPulse app.
        .library(name: "ShipPulseKitCore", targets: ["ShipPulseKitCore"]),
    ],
    targets: [
        .target(name: "ShipPulseKitCore"),
        // Catches exceptions CloudKit raises when it opens a container.
        .target(name: "ShipPulseKitObjC"),
        .target(name: "ShipPulseKit", dependencies: ["ShipPulseKitCore", "ShipPulseKitObjC"]),
        .testTarget(name: "ShipPulseKitTests", dependencies: ["ShipPulseKit", "ShipPulseKitCore"]),
    ]
)
