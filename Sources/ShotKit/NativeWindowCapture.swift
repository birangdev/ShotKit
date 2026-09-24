#if os(macOS)
import AppKit
import ScreenCaptureKit
import SwiftUI

/// Which compositor API produces the bitmap.
///
/// Both ask the WindowServer for the window as drawn, so both capture the
/// sidebar materials and vibrancy that a view-hierarchy snapshot renders blank.
/// They differ only in what macOS demands before handing the pixels over.
public enum NativeWindowCaptureMethod: Sendable {
    /// `SCScreenshotManager`. Current API, but macOS gates it behind Screen
    /// Recording for *every* window, including the caller's own.
    case screenCaptureKit

    /// `CGWindowListCreateImage`. Deprecated in macOS 14, and it cannot capture
    /// another process's windows without Screen Recording — but a process
    /// capturing its own windows needs no grant at all, which keeps unsigned
    /// development builds and CI working.
    case windowServer

    /// ScreenCaptureKit when Screen Recording is already granted, WindowServer
    /// otherwise. Prefers the supported API without making an export tool
    /// depend on a TCC prompt that cannot be answered in-process.
    case automatic
}

/// Settings for a real macOS window, before it becomes part of a marketing card.
public struct NativeWindowConfiguration {
    public var title: String
    /// The content viewport in points. The native title bar adds to the image height.
    /// Scrolling content remains clipped to this viewport, as it is in the app.
    public var contentSize: CGSize
    /// Output pixels per point, independent of the display's backing scale.
    public var scale: CGFloat
    /// Nil inherits the application's appearance.
    public var appearance: NSAppearance?
    /// Which compositor API to use. Defaults to `.automatic`.
    public var method: NativeWindowCaptureMethod

    public init(
        title: String,
        contentSize: CGSize,
        scale: CGFloat = 2,
        appearance: NSAppearance? = nil,
        method: NativeWindowCaptureMethod = .automatic
    ) {
        self.title = title
        self.contentSize = contentSize
        self.scale = scale
        self.appearance = appearance
        self.method = method
    }
}

public enum NativeWindowCaptureError: Error, LocalizedError {
    case invalidGeometry
    case screenRecordingPermissionRequired
    case windowNotVisible
    case windowNotFound
    case pngEncodingFailed

    public var errorDescription: String? {
        switch self {
        case .invalidGeometry:
            return "Window dimensions and scale must be finite, positive, and produce at least one pixel per axis."
        case .screenRecordingPermissionRequired:
            return "Allow Screen Recording for the capturing application in System Settings, then retry."
        case .windowNotVisible:
            return "Show the window before capturing it."
        case .windowNotFound:
            return "The window is not available from ScreenCaptureKit."
        case .pngEncodingFailed:
            return "The captured window could not be encoded as PNG."
        }
    }
}

/// A captured native window, including its title bar but excluding its outer shadow.
/// Put this view inside `ShotCard(framed: false)` without adding `WindowChrome`.
/// Its fixed logical size lets the card scale pixels without relaying out the UI.
public struct WindowSnapshot: View {
    public let cgImage: CGImage
    public let pointSize: CGSize

    public var body: some View {
        Image(decorative: cgImage, scale: 1)
            .resizable()
            .frame(width: pointSize.width, height: pointSize.height)
    }

    public func pngData() throws -> Data {
        guard let data = NSBitmapImageRep(cgImage: cgImage)
            .representation(using: .png, properties: [:]) else {
            throw NativeWindowCaptureError.pngEncodingFailed
        }
        return data
    }
}

@available(macOS 14.0, *)
public extension ShotKit {
    /// Captures an existing visible window with its actual native frame and toolbar.
    /// This is the most faithful option for a window configured by a SwiftUI Scene.
    /// Does not resize, activate, close, or change the appearance of the supplied window.
    ///
    /// Never prompts. With `.screenCaptureKit` the Screen Recording grant must
    /// already be in place; `.automatic` falls back to the WindowServer instead
    /// of failing, and the WindowServer needs no grant for the caller's own windows.
    @MainActor
    static func captureWindow(
        _ window: NSWindow,
        scale: CGFloat = 2,
        method: NativeWindowCaptureMethod = .automatic
    ) async throws -> WindowSnapshot {
        _ = try NativeWindowCapture.pixelSize(for: window.frame.size, scale: scale)
        guard window.isVisible, !window.isMiniaturized else {
            throw NativeWindowCaptureError.windowNotVisible
        }
        let resolved = try NativeWindowCapture.resolve(method)

        try Task.checkCancellation()
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        if resolved == .windowServer {
            return try await NativeWindowCapture.captureThroughWindowServer(window, scale: scale)
        }

        let available = try await SCShareableContent.excludingDesktopWindows(
            true, onScreenWindowsOnly: true
        )
        guard let source = available.windows.first(where: {
            $0.windowID == CGWindowID(window.windowNumber)
        }) else {
            throw NativeWindowCaptureError.windowNotFound
        }
        let filter = SCContentFilter(desktopIndependentWindow: source)
        let size = filter.contentRect.size
        let pixels = try NativeWindowCapture.pixelSize(for: size, scale: scale)
        let settings = SCStreamConfiguration()
        settings.width = pixels.width
        settings.height = pixels.height
        settings.showsCursor = false
        settings.ignoreShadowsSingleWindow = true
        // SCStreamConfiguration.backgroundColor is unowned(unsafe): assigning a
        // temporary leaves it dangling. Hold the colour for the capture's life.
        settings.backgroundColor = NativeWindowCapture.transparentBackground
        settings.scalesToFit = true

        try Task.checkCancellation()
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: settings
        )
        try Task.checkCancellation()
        return WindowSnapshot(cgImage: image, pointSize: size)
    }

    /// Hosts a view in a titled window at the requested content size, then captures
    /// its composited appearance. Requires macOS 14 and Screen Recording permission.
    ///
    /// `configure` can match the app's toolbar style and title-bar configuration.
    /// `prepare` runs after the window is shown: await fixture loading or other
    /// app-specific readiness here. ShotKit then lays out and allows a compositor
    /// update; this is not a substitute for waiting for your application's data.
    ///
    /// The temporary window becomes key and the app is activated. On success,
    /// failure, or cancellation, it closes and the previous visible key window
    /// is restored. Captures should be run sequentially.
    @MainActor
    static func captureWindow<Content: View>(
        configuration: NativeWindowConfiguration,
        configure: (NSWindow) -> Void = { _ in },
        prepare: (NSWindow) async throws -> Void = { _ in },
        @ViewBuilder content: () -> Content
    ) async throws -> WindowSnapshot {
        _ = try NativeWindowCapture.pixelSize(for: configuration.contentSize, scale: configuration.scale)
        // Resolved up front so an impossible request fails before a window is
        // put on screen, rather than after the user watches one appear.
        _ = try NativeWindowCapture.resolve(configuration.method)
        return try await NativeWindowCapture.withWindow(
            configuration: configuration,
            configure: configure,
            prepare: prepare,
            content: content
        ) { window in
            try await captureWindow(window, scale: configuration.scale, method: configuration.method)
        }
    }
}

/// The window lifecycle is separate from screen capture so it can be tested
/// without Screen Recording permission or capturing anything on the user's screen.
@MainActor
enum NativeWindowCapture {
    /// Retained because `SCStreamConfiguration.backgroundColor` does not retain.
    static let transparentBackground = CGColor(red: 0, green: 0, blue: 0, alpha: 0)

    static func pixelSize(for size: CGSize, scale: CGFloat) throws -> (width: Int, height: Int) {
        let width = (size.width * scale).rounded()
        let height = (size.height * scale).rounded()
        guard size.width.isFinite, size.height.isFinite, scale.isFinite,
              size.width > 0, size.height > 0, scale > 0,
              width >= 1, height >= 1,
              width < CGFloat(Int.max), height < CGFloat(Int.max) else {
            throw NativeWindowCaptureError.invalidGeometry
        }
        return (Int(width), Int(height))
    }

    /// Picks the concrete API, and reports the one case that cannot proceed:
    /// ScreenCaptureKit demanded explicitly without the grant it requires.
    static func resolve(_ method: NativeWindowCaptureMethod) throws -> NativeWindowCaptureMethod {
        switch method {
        case .windowServer:
            return .windowServer
        case .screenCaptureKit:
            guard CGPreflightScreenCaptureAccess() else {
                throw NativeWindowCaptureError.screenRecordingPermissionRequired
            }
            return .screenCaptureKit
        case .automatic:
            return CGPreflightScreenCaptureAccess() ? .screenCaptureKit : .windowServer
        }
    }

    /// Sizes the window so its content view matches `size` exactly.
    static func applyContentSize(_ size: CGSize, to window: NSWindow) {
        let target = window.frameRect(forContentRect: CGRect(origin: window.frame.origin, size: size))
        if window.frame.size != target.size {
            window.setFrame(target, display: false)
        }
        // A content view that spans the full frame (as it can once the window
        // is on screen) needs the difference taken off explicitly.
        if let content = window.contentView, content.bounds.height != size.height {
            let overshoot = content.bounds.height - size.height
            var corrected = window.frame
            corrected.size.height -= overshoot
            window.setFrame(corrected, display: false)
        }
    }

    static func makeWindow<Content: View>(
        configuration: NativeWindowConfiguration,
        configure: (NSWindow) -> Void,
        content: Content
    ) throws -> NSWindow {
        _ = try pixelSize(for: configuration.contentSize, scale: configuration.scale)
        let host = NSHostingController(rootView: content)
        // The requested viewport, not the view's ideal size, owns window sizing.
        host.sizingOptions = []
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: configuration.contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = configuration.title
        window.appearance = configuration.appearance
        window.contentViewController = host
        configure(window)
        // setContentSize is measured against the window's current style, so a
        // titled window (or one whose toolbar style `configure` just changed)
        // can come back a title bar taller than asked. Sizing from the content
        // rect and then correcting states the intent exactly.
        applyContentSize(configuration.contentSize, to: window)
        window.center()
        return window
    }

    static func withWindow<Content: View, Result>(
        configuration: NativeWindowConfiguration,
        configure: (NSWindow) -> Void = { _ in },
        prepare: (NSWindow) async throws -> Void = { _ in },
        content: () -> Content,
        operation: (NSWindow) async throws -> Result
    ) async throws -> Result {
        try Task.checkCancellation()
        // NSApp.keyWindow lags makeKeyAndOrderFront by a turn, so a caller that
        // just brought its own window forward would otherwise have nothing
        // restored. Fall back through mainWindow to the frontmost visible one.
        let previousKeyWindow = NSApp.keyWindow
            ?? NSApp.mainWindow
            // `NSApp.windows` is creation order, not z-order, so taking the
            // first visible one restores whichever window happens to be oldest
            // — and leaves the window that was actually in front buried behind
            // it. `orderedIndex` is the screen list, where lower is nearer the
            // front, so the minimum is the frontmost window.
            ?? NSApp.windows
                .filter { $0.isVisible && !$0.isMiniaturized }
                .min { $0.orderedIndex < $1.orderedIndex }
        let window = try makeWindow(configuration: configuration, configure: configure, content: content())
        defer {
            window.orderOut(nil)
            window.close()
            if let previousKeyWindow, previousKeyWindow.isVisible {
                previousKeyWindow.makeKeyAndOrderFront(nil)
            }
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Ordering a titled window on screen can revise its content height, so
        // the requested viewport is re-asserted once it is actually visible.
        // The viewport is the contract here: it decides what the capture shows,
        // and scrolling content stays clipped to it exactly as in the app.
        applyContentSize(configuration.contentSize, to: window)
        try await prepare(window)
        try Task.checkCancellation()
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        // Yield the main actor so AppKit/SwiftUI and the compositor can commit
        // the layout. Unlike RunLoop.run, this supports async readiness/cancellation.
        try await Task.sleep(nanoseconds: 100_000_000)
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        return try await operation(window)
    }
}
#endif
