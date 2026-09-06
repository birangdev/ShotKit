// swift-tools-version: 5.9
import PackageDescription

// ShotKit — a small, project-agnostic App Store screenshot engine. It renders
// `ScreenshotScene`s in a real off-screen window and captures the live view
// hierarchy (AppKit controls and Charts included), then composes marketing cards
// around them. It references no app-specific types, so any project can supply its
// own scenes.
//
// Built as a `.static` library so that when the only callers are compiled out
// (e.g. behind `#if DEBUG`), the linker drops it from the shipping binary.
let package = Package(
    name: "ShotKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "ShotKit", type: .static, targets: ["ShotKit"])
    ],
    targets: [
        .target(name: "ShotKit"),
        // Example targets. These are never pulled into a consumer's build (only
        // the `ShotKit` library product is), so they don't ship — they just let
        // `swift run CafeExportTool <folder>` regenerate the example screenshots
        // and keep the example compiling against the library.
        .target(
            name: "CafeExample",
            dependencies: ["ShotKit"],
            path: "Examples/CafeApp",
            exclude: ["README.md", "ExportTool", "ComparisonTool", "Screenshots"]
        ),
        .executableTarget(
            name: "CafeExportTool",
            dependencies: ["ShotKit", "CafeExample"],
            path: "Examples/CafeApp/ExportTool"
        ),
        // Regenerates the ImageRenderer-vs-ShotKit comparison in the README:
        // `swift run ComparisonTool Examples/CafeApp/Screenshots`.
        .executableTarget(
            name: "ComparisonTool",
            dependencies: ["ShotKit", "CafeExample"],
            path: "Examples/CafeApp/ComparisonTool"
        ),
        .testTarget(name: "ShotKitTests", dependencies: ["ShotKit"])
    ]
)
