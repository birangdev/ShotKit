// This tool drives macOS-only APIs (`NSApplication`, ShotKit's `cacheDisplay`
// capture) and is only ever run on a Mac. It's guarded so the whole package
// still compiles on iOS/Linux — e.g. the Swift Package Index compatibility
// build, which builds every target for every declared platform.
#if os(macOS)
import AppKit
import CafeExample
import ShotKit

@main
struct ExportTool {
    @MainActor
    static func main() {
        // Bring up an accessory app so SwiftUI / AppKit can lay out and draw the
        // views before ShotKit snapshots them.
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()

        let args = CommandLine.arguments
        let folder = URL(fileURLWithPath: args.count > 1 ? args[1] : FileManager.default.currentDirectoryPath)
        let urls = ShotKit.export(CafeExampleScenes.all, to: folder)
        for url in urls { print(url.path) }
    }
}
#else
@main
struct ExportTool {
    static func main() {
        print("CafeExportTool runs on macOS only.")
    }
}
#endif
