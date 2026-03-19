// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FastSwitcher",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "FastSwitcher",
            path: "Sources/FastSwitcher",
            linkerSettings: [
                .unsafeFlags(["-framework", "Cocoa"]),
                .unsafeFlags(["-framework", "Carbon"]),
            ]
        ),
    ]
)
