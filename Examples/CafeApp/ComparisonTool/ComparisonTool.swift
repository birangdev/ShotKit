// Renders `ControlsPanel` with SwiftUI's `ImageRenderer`, then lets ShotKit
// compose the finished ImageRenderer-vs-ShotKit comparison and writes it as
// `renderer-comparison.png` into the folder passed as the first argument.
//
//   swift run ComparisonTool Examples/CafeApp/Screenshots
//
// Guarded to macOS: it uses `NSApplication` and `ImageRenderer.nsImage`, and is
// only run on a Mac. The stub keeps the whole package compiling on iOS/Linux
// (e.g. the Swift Package Index compatibility build).
#if os(macOS)
import AppKit
import CafeExample
import ShotKit
import SwiftUI

@main
struct ComparisonTool {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()

        let args = CommandLine.arguments
        let folder = URL(
            fileURLWithPath: args.count > 1 ? args[1] : FileManager.default.currentDirectoryPath
        )

        let panel = ControlsPanel()
            .frame(width: 460, height: 560)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: panel)
        renderer.scale = 2
        let rendererImage = renderer.nsImage.map(Image.init(nsImage:))
            ?? Image(systemName: "questionmark")

        let scene = RendererComparisonScene(rendererImage: rendererImage)
        guard let data = ShotKit.capturePNG(scene) else {
            FileHandle.standardError.write(Data("comparison capture failed\n".utf8))
            exit(1)
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("renderer-comparison.png")
        try? data.write(to: url)
        print(url.path)
    }
}
#else
@main
struct ComparisonTool {
    static func main() {
        print("ComparisonTool runs on macOS only.")
    }
}
#endif
