#if os(macOS)
import AppKit
import Darwin
import ShotKit
import SwiftUI

/// A real NavigationSplitView fixture. It contains no app-specific implementation
/// or live account data; it exercises native sidebar, form, and toolbar rendering.
private struct SampleSettings: View {
    @State private var selection: String? = "Claude"

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("General") {
                    Label("General", systemImage: "gearshape").tag("General")
                    Label("Menu Bar", systemImage: "menubar.rectangle").tag("Menu Bar")
                    Label("Notifications", systemImage: "bell").tag("Notifications")
                }
                Section("Providers") {
                    Label("Claude", systemImage: "circle.fill").tag("Claude")
                    Label("Codex", systemImage: "circle").tag("Codex")
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            Form {
                Section("Status") {
                    LabeledContent("Connection") {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    LabeledContent("Detected", value: "Ready")
                    LabeledContent("Last usage data", value: "Just now")
                }
                Section("Live limits") {
                    LabeledContent("5-hour limit", value: "66% left")
                    LabeledContent("Weekly", value: "78% left")
                }
                Section("History") {
                    LabeledContent("Daily history", value: "No history found")
                    LabeledContent("History cache", value: "Not imported")
                    Button("Clear quota observations") {}
                }
            }
            .formStyle(.grouped)
            .navigationTitle(selection ?? "Settings")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {} label: { Image(systemName: "arrow.clockwise") }
                        .help("Refresh")
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

private struct LegacySettingsScene: ScreenshotScene {
    let size: CGSize
    var spec: ScreenshotSpec { ScreenshotSpec("legacy", pointSize: AppStoreSize.macPoints) }

    @MainActor func makeContent() -> AnyView {
        AnyView(
            ShotCard("Set it up once, then forget it",
                     subtitle: "Launch at login, notifications, and privacy on your terms",
                     framed: false) {
                WindowChrome(title: "ShotKit Sample — Settings") {
                    SampleSettings().frame(width: size.width, height: size.height)
                }
            }
        )
    }
}

@available(macOS 14.0, *)
private final class ExportDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do {
                try await exportSamples()
                NSApp.terminate(nil)
            } catch {
                FileHandle.standardError.write(Data("Native window export failed: \(error.localizedDescription)\n".utf8))
                exit(EXIT_FAILURE)
            }
        }
    }

    @MainActor
    private func exportSamples() async throws {
        let args = CommandLine.arguments.dropFirst()
        guard let destination = args.first, !destination.hasPrefix("--") else {
            throw ExportError.usage
        }
        if !CGPreflightScreenCaptureAccess() {
            if args.contains("--request-screen-recording") { _ = CGRequestScreenCaptureAccess() }
            guard CGPreflightScreenCaptureAccess() else {
                throw NativeWindowCaptureError.screenRecordingPermissionRequired
            }
        }
        let folder = URL(fileURLWithPath: destination, isDirectory: true)
            .appendingPathComponent("shotkit-native-\(Int(Date().timeIntervalSince1970))", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        for size in [CGSize(width: 800, height: 520), CGSize(width: 1000, height: 650)] {
            let label = "\(Int(size.width))x\(Int(size.height))"
            let snapshot = try await ShotKit.captureWindow(
                configuration: NativeWindowConfiguration(
                    title: "ShotKit Sample — Settings", contentSize: size,
                    appearance: NSAppearance(named: .darkAqua)
                ),
                configure: { $0.toolbarStyle = .unified }
            ) {
                SampleSettings()
            }
            try write(snapshot.pngData(), named: "native-window-\(label).png", to: folder)

            // Only the bitmap and marketing text reach ImageRenderer. Native
            // controls were already captured by ScreenCaptureKit at full size.
            let card = ShotCard(
                "Set it up once, then forget it",
                subtitle: "Launch at login, notifications, and privacy on your terms",
                framed: false
            ) {
                snapshot.shadow(color: .black.opacity(0.5), radius: 30, y: 18)
            }
            .frame(width: AppStoreSize.macPoints.width, height: AppStoreSize.macPoints.height)
            .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: card)
            renderer.scale = 2
            guard let image = renderer.cgImage,
                  let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                throw NativeWindowCaptureError.pngEncodingFailed
            }
            try write(data, named: "native-card-\(label).png", to: folder)

            guard let legacy = ShotKit.capturePNG(LegacySettingsScene(size: size)) else {
                throw ExportError.legacyCaptureFailed
            }
            try write(legacy, named: "legacy-card-\(label).png", to: folder)
        }
    }

    private func write(_ data: Data, named name: String, to folder: URL) throws {
        let url = folder.appendingPathComponent(name)
        try data.write(to: url, options: .withoutOverwriting)
        print(url.path)
    }

    private enum ExportError: Error, LocalizedError {
        case usage, legacyCaptureFailed
        var errorDescription: String? {
            switch self {
            case .usage: return "Usage: NativeWindowExportTool <output-folder> [--request-screen-recording]"
            case .legacyCaptureFailed: return "The legacy comparison capture failed."
            }
        }
    }
}

@main
struct NativeWindowExportTool {
    @MainActor
    static func main() {
        guard #available(macOS 14.0, *) else {
            FileHandle.standardError.write(Data("Native window capture requires macOS 14 or later.\n".utf8))
            exit(EXIT_FAILURE)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = ExportDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
#else
@main
struct NativeWindowExportTool {
    static func main() { print("NativeWindowExportTool requires macOS 14 or later.") }
}
#endif
