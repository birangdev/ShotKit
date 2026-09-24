import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - ShotKit — a small, project-agnostic App Store screenshot engine.
//
// Nothing here references app-specific types. Each project supplies its own
// `ScreenshotScene`s; ShotKit renders and writes them. The composition layer is
// pure SwiftUI; only the rasterizer is platform-specific (AppKit on macOS,
// UIKit on iOS).

/// A single screenshot's output geometry and filename.
public struct ScreenshotSpec {
    public var name: String
    /// Logical size in points. Pixel size = pointSize * scale.
    public var pointSize: CGSize
    public var scale: CGFloat

    public init(_ name: String, pointSize: CGSize = AppStoreSize.macPoints, scale: CGFloat = 2) {
        self.name = name
        self.pointSize = pointSize
        self.scale = scale
    }

    /// The output resolution in pixels: `pointSize * scale`.
    public var pixelSize: CGSize {
        CGSize(width: pointSize.width * scale, height: pointSize.height * scale)
    }
}

/// Standard App Store canvas sizes. `pointSize * scale` must equal a pixel size
/// the App Store accepts. The macOS values pair with the default `scale` of 2;
/// the iOS values note the scale to pass (usually 3 for iPhone, 2 for iPad).
public enum AppStoreSize {
    // macOS
    public static let macPoints = CGSize(width: 1440, height: 900)     // x2 = 2880x1800
    public static let macPointsAlt = CGSize(width: 1280, height: 800)  // x2 = 2560x1600

    // iOS (pass the noted scale to ScreenshotSpec)
    public static let iPhone67 = CGSize(width: 430, height: 932)       // x3 = 1290x2796 (6.7"/6.9")
    public static let iPhone65 = CGSize(width: 414, height: 896)       // x3 = 1242x2688 (6.5")
    public static let iPad13 = CGSize(width: 1024, height: 1366)       // x2 = 2048x2732 (12.9"/13")
}

/// How a scene is turned into pixels.
///
/// The difference matters for anything the WindowServer composites rather than
/// the view drawing itself: `NavigationSplitView` sidebars, sheets, translucent
/// toolbars. Those are invisible to a view-hierarchy snapshot, which is why
/// they come out blank.
public enum CaptureMethod: Sendable {
    /// Snapshot the view's own drawing (`cacheDisplay`). No permissions, but
    /// materials and vibrancy capture as blank.
    case viewHierarchy

    /// Ask the WindowServer for the composited window, exactly as it appears on
    /// screen. Captures materials correctly.
    ///
    /// Needs no Screen Recording permission: a process capturing its own windows
    /// is not a privacy boundary, and this only ever captures the window ShotKit
    /// just created. (ScreenCaptureKit is gated even for a caller's own windows,
    /// which is why `NativeWindowCaptureMethod.automatic` falls back to this.)
    /// Still opt-in, because the view-hierarchy path is cheaper and sufficient
    /// for anything that is not a material.
    case windowServer
}

/// A unit of work: a caption + a view, rendered at a spec.
public protocol ScreenshotScene {
    var spec: ScreenshotSpec { get }
    @MainActor func makeContent() -> AnyView
}

public enum ShotKit {
    /// Captures a scene by rendering it in a real off-screen window and grabbing
    /// the live view hierarchy — not `ImageRenderer`.
    ///
    /// `ImageRenderer` rasterizes SwiftUI's own drawing but drops platform-backed
    /// controls: segmented `Picker`s, linear `ProgressView`s, `Slider`s,
    /// `Toggle`s, and the like come out as a "no-entry" placeholder, and
    /// `ScrollView` content below the fold can be missing — so it can't capture
    /// the true UI. Hosting the view in a real window and snapshotting it
    /// (`cacheDisplay` on macOS, `drawHierarchy` on iOS) renders exactly what the
    /// user sees, at the screen's backing scale.
    @MainActor
    public static func capturePNG(
        _ scene: ScreenshotScene,
        using method: CaptureMethod = .viewHierarchy
    ) -> Data? {
        let spec = scene.spec
        let content = AnyView(
            scene.makeContent()
                .frame(width: spec.pointSize.width, height: spec.pointSize.height)
                .environment(\.colorScheme, .dark)
        )
        return rasterize(content, spec: spec, method: method)
    }

    /// Captures every scene and writes `<name>.png` into `folder`. Returns the
    /// URLs written. Creates the folder if needed.
    @MainActor
    @discardableResult
    public static func export(
        _ scenes: [ScreenshotScene],
        to folder: URL,
        using method: CaptureMethod = .viewHierarchy
    ) -> [URL] {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var written: [URL] = []
        for scene in scenes {
            guard let data = capturePNG(scene, using: method) else { continue }
            let url = folder.appendingPathComponent("\(scene.spec.name).png")
            if (try? data.write(to: url)) != nil { written.append(url) }
        }
        return written
    }

    #if canImport(AppKit)
    /// macOS: host in a borderless `NSWindow`, then `cacheDisplay` the hierarchy.
    @MainActor
    private static func rasterize(
        _ content: AnyView,
        spec: ScreenshotSpec,
        method: CaptureMethod = .viewHierarchy
    ) -> Data? {
        let hosting = NSHostingView(rootView: content)
        hosting.frame = CGRect(origin: .zero, size: spec.pointSize)

        // Borderless, so the capture is exactly the content: a titled window
        // adds a title-bar band and rounds the corners, both of which end up in
        // the image. `ActivationAnchor` is what makes an app whose only visible
        // window is borderless still able to activate.
        ActivationAnchor.ensure()
        let window = KeyableWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(calibratedWhite: 0.13, alpha: 1)
        window.contentView = hosting
        // Must be on-screen for SwiftUI/Charts to lay out and draw; a borderless
        // window that we order out immediately after keeps the flash minimal.
        window.orderFrontRegardless()
        // Key and active, or AppKit draws every control unemphasized: a selected
        // segment loses its accent fill, a progress bar loses its tint. That is
        // not what the user sees, so it is not what the shot should show.
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Give SwiftUI, Charts, and AppKit controls a few run-loop passes to lay
        // out and render before we snapshot the hierarchy.
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        defer { window.orderOut(nil) }

        switch method {
        case .windowServer:
            // The composited window, materials included.
            return compositedPNG(of: window, pixelSize: spec.pixelSize)
        case .viewHierarchy:
            let bounds = hosting.bounds
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
            hosting.cacheDisplay(in: bounds, to: rep)
            return rep.representation(using: .png, properties: [:])
        }
    }

    /// Keeps the app activatable while only borderless windows are on screen.
    ///
    /// macOS will not activate an app whose only window is borderless, and an
    /// inactive app draws every control in its unemphasized state — a selected
    /// segment loses its accent fill, a popup its tint. One off-screen titled
    /// window, created once and left alive, is enough for activation to stick.
    /// It is never captured: the WindowServer is asked for one window id.
    @MainActor
    private enum ActivationAnchor {
        private static var anchor: NSWindow?

        static func ensure() {
            if anchor == nil {
                let window = NSWindow(
                    contentRect: NSRect(x: -10_000, y: -10_000, width: 1, height: 1),
                    styleMask: [.titled],
                    backing: .buffered,
                    defer: false
                )
                window.isReleasedWhenClosed = false
                window.orderFrontRegardless()
                anchor = window
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// A borderless window that can still take key.
    ///
    /// `NSWindow` refuses key status to a borderless window by default, and an
    /// unemphasized window renders its controls in the greyed-out state macOS
    /// uses for background apps.
    private final class KeyableWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }

    /// Asks the WindowServer for the window as drawn on screen.
    ///
    /// `.boundsIgnoreFraming` excludes the window's shadow from the bounds (not
    /// the title bar, which a borderless window has none of anyway);
    /// `.bestResolution` keeps the Retina backing scale.
    @MainActor
    private static func compositedPNG(of window: NSWindow, pixelSize: CGSize) -> Data? {
        let id = CGWindowID(window.windowNumber)
        guard id != 0 else { return nil }

        // Deprecated in macOS 14 in favour of ScreenCaptureKit, which is async
        // and needs a capture session. For a synchronous dev-time tool this
        // stays the pragmatic choice; swap it here if it is ever removed.
        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            id,
            [.boundsIgnoreFraming, .bestResolution]
        ) else { return nil }

        // The WindowServer hands back a pixel or two beyond the window's own
        // bounds, so a 1440x900 window captures as 1442x902 points. The App
        // Store rejects anything that is not exactly the size it asked for, so
        // trim back to the spec rather than shipping an off-by-four image.
        let rep = NSBitmapImageRep(cgImage: cropped(image, to: pixelSize))
        return rep.representation(using: .png, properties: [:])
    }

    /// Centre-crops to `size`, or returns the image when it already matches.
    private static func cropped(_ image: CGImage, to size: CGSize) -> CGImage {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard image.width != width || image.height != height,
              image.width >= width, image.height >= height else { return image }
        let origin = CGPoint(
            x: ((image.width - width) / 2),
            y: ((image.height - height) / 2)
        )
        return image.cropping(
            to: CGRect(x: origin.x, y: origin.y, width: CGFloat(width), height: CGFloat(height))
        ) ?? image
    }
    #elseif canImport(UIKit)
    /// iOS: host in a `UIWindow` attached to the active scene, then snapshot the
    /// live hierarchy with `drawHierarchy` at the spec's scale.
    ///
    /// `method` is accepted and ignored: `.windowServer` describes a macOS
    /// compositor that has no iOS equivalent, and `drawHierarchy` already
    /// captures what is actually on screen. The parameter stays in the signature
    /// so `capturePNG` has one call shape on every platform.
    @MainActor
    private static func rasterize(
        _ content: AnyView,
        spec: ScreenshotSpec,
        method: CaptureMethod = .viewHierarchy
    ) -> Data? {
        let host = UIHostingController(rootView: content)
        host.overrideUserInterfaceStyle = .dark
        host.view.frame = CGRect(origin: .zero, size: spec.pointSize)

        let window = UIWindow(frame: host.view.frame)
        // Attaching to a foreground scene lets the hierarchy render for real
        // (drawHierarchy afterScreenUpdates needs an on-screen window).
        if let scene = activeWindowScene() { window.windowScene = scene }
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.isHidden = false
        window.layoutIfNeeded()
        host.view.layoutIfNeeded()

        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        let format = UIGraphicsImageRendererFormat()
        format.scale = spec.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(bounds: host.view.bounds, format: format)
        let image = renderer.image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        return image.pngData()
    }

    @MainActor
    private static func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }
    #else
    @MainActor
    private static func rasterize(
        _ content: AnyView,
        spec: ScreenshotSpec,
        method: CaptureMethod = .viewHierarchy
    ) -> Data? { nil }
    #endif
}

// MARK: - Deterministic scaling

/// Scales its single child by `scale` while reserving the *scaled* size in
/// layout. A plain `scaleEffect` only transforms the drawing and keeps the
/// natural footprint, so scaled content silently overflows and gets clipped by a
/// fixed-size frame. Doing the bookkeeping in a `Layout` keeps the reserved size
/// exact in a single pass.
public struct ScaledLayout: Layout {
    public var scale: CGFloat

    public init(scale: CGFloat) {
        self.scale = scale
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let natural = subviews[0].sizeThatFits(.unspecified)
        return CGSize(width: natural.width * scale, height: natural.height * scale)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Placed at natural size, centered; the child's own `scaleEffect` draws
        // it scaled about that same center, so it exactly fills the reserved box.
        subviews[0].place(
            at: CGPoint(x: bounds.midX, y: bounds.midY),
            anchor: .center,
            proposal: .unspecified
        )
    }
}

/// A view that draws `content` at `scale` and occupies the matching scaled size.
public struct ScaledContent<Content: View>: View {
    public let scale: CGFloat
    @ViewBuilder public let content: () -> Content

    public init(scale: CGFloat, @ViewBuilder content: @escaping () -> Content) {
        self.scale = scale
        self.content = content
    }

    public var body: some View {
        ScaledLayout(scale: scale) {
            content().scaleEffect(scale, anchor: .center)
        }
    }
}

// MARK: - Composition helpers (headline + background + framed content)

/// Which edge the caption sits on, relative to the framed content.
///
/// `.top` and `.bottom` stack vertically with centered text, the classic App
/// Store hero. `.leading` and `.trailing` place the caption beside the content
/// with left-aligned text, which leaves room for a feature list or supporting
/// detail next to the screenshot.
public enum CaptionPlacement: Sendable {
    case top
    case bottom
    case leading
    case trailing

    var isHorizontal: Bool { self == .leading || self == .trailing }
}

/// A marketing "card": gradient background, an optional big headline, and the
/// app view arranged with it, framed with a rounded window border and shadow.
///
/// Pass `title: nil` (and `subtitle: nil`) to omit the caption entirely — you
/// still get the framed, auto-fit shot, just without any text over it.
///
/// The whole column (caption + framed window) is auto-scaled to fit the canvas
/// via `ViewThatFits`, which picks the largest candidate scale whose reserved
/// size (see `ScaledContent`) actually fits. That keeps a compact view large and
/// prominent while a much taller window shrinks just enough to be captured
/// whole — no per-scene tuning, and nothing clips.
public struct ShotCard<Background: View, Detail: View, Content: View>: View {
    /// Small label above the headline, the usual marketing eyebrow. It also
    /// earns its keep structurally: without it a top-aligned caption sits hard
    /// against the canvas edge, which reads as unplaced rather than deliberate.
    public let eyebrow: String?
    /// SF Symbol shown in a tinted tile beside the eyebrow.
    public let eyebrowSymbol: String?
    public let title: String?
    public let subtitle: String?
    public let accent: Color
    /// When true (default) the content gets a rounded "window" frame + border +
    /// shadow (right for a Mac window). Set false when the content supplies its
    /// own shape — e.g. a `DeviceFrame` iPhone mockup — so it isn't double-framed.
    public let framed: Bool
    /// Which edge the caption occupies. Defaults to `.top`.
    public let placement: CaptionPlacement
    /// For side placements, how far below the content's top edge the caption
    /// starts. Flush alignment reads as accidental: a headline's cap-height
    /// already sits below its bounding box, so a small deliberate inset is what
    /// makes the column look placed rather than merely aligned.
    public let captionTopInset: CGFloat
    /// Extra detail rendered under the subtitle. Most useful with a side
    /// placement, where there is room for a feature list.
    @ViewBuilder public let detail: () -> Detail
    @ViewBuilder public let background: () -> Background
    @ViewBuilder public let content: () -> Content

    public init(
        _ title: String? = nil,
        subtitle: String? = nil,
        eyebrow: String? = nil,
        eyebrowSymbol: String? = nil,
        accent: Color = .green,
        framed: Bool = true,
        placement: CaptionPlacement = .top,
        captionTopInset: CGFloat = 56,
        @ViewBuilder background: @escaping () -> Background,
        @ViewBuilder detail: @escaping () -> Detail,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.captionTopInset = captionTopInset
        self.eyebrow = eyebrow
        self.eyebrowSymbol = eyebrowSymbol
        self.title = title
        self.subtitle = subtitle
        self.accent = accent
        self.framed = framed
        self.placement = placement
        self.background = background
        self.detail = detail
        self.content = content
    }

    private var hasCaption: Bool { title != nil || subtitle != nil || eyebrow != nil }

    public var body: some View {
        ZStack {
            background()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Candidate scales, largest first. `ViewThatFits` renders the first
            // whose (accurately reserved) size fits. A compact view lands near
            // the top of the range; tall windows drop to a smaller step
            // automatically. Listed explicitly rather than via `ForEach` so each
            // is treated as its own fit candidate.
            //
            // Side placements must fit horizontally too, since the caption and
            // the content compete for width; stacked ones only ever run out of
            // height.
            ViewThatFits(in: placement.isHorizontal ? [.horizontal, .vertical] : .vertical) {
                arrangement(scale: 1.3)
                arrangement(scale: 1.15)
                arrangement(scale: 1.0)
                arrangement(scale: 0.9)
                arrangement(scale: 0.8)
                arrangement(scale: 0.72)
                arrangement(scale: 0.64)
                arrangement(scale: 0.56)
                arrangement(scale: 0.48)
                arrangement(scale: 0.4)
            }
        }
    }

    @ViewBuilder
    private func arrangement(scale: CGFloat) -> some View {
        ScaledContent(scale: scale) {
            switch placement {
            case .top:
                VStack(spacing: 44) { captionBlock; framedContent }
            case .bottom:
                VStack(spacing: 44) { framedContent; captionBlock }
            // Top-aligned: against a tall screenshot a centred caption floats
            // at mid-height, which reads as unplaced. Anchoring both columns to
            // the same line is what a two-column marketing layout wants.
            case .leading:
                HStack(alignment: .top, spacing: 64) { captionBlock; framedContent }
            case .trailing:
                HStack(alignment: .top, spacing: 64) { framedContent; captionBlock }
            }
        }
        // Constant margin (outside the scale) so the fitted arrangement always
        // keeps breathing room against the canvas edges.
        .padding(56)
    }

    @ViewBuilder private var captionBlock: some View {
        if hasCaption || Detail.self != EmptyView.self {
            VStack(alignment: placement.isHorizontal ? .leading : .center, spacing: 12) {
                if let eyebrow {
                    HStack(spacing: 11) {
                        if let eyebrowSymbol {
                            Image(systemName: eyebrowSymbol)
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(accent)
                                .frame(width: 44, height: 44)
                                .background(accent.opacity(0.16),
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        Text(eyebrow)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                    .padding(.bottom, 6)
                }
                if let title {
                    Text(title)
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .multilineTextAlignment(placement.isHorizontal ? .leading : .center)
                        .foregroundStyle(.white)
                        // Beside the content the caption is width-capped, so a
                        // long headline must wrap onto another line. Without
                        // this it truncates instead, since the auto-fit scales
                        // the arrangement but never reflows text.
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 25, weight: .regular))
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(placement.isHorizontal ? .leading : .center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                detail()
                    .padding(.top, hasCaption ? 26 : 0)
            }
            // Beside the content a caption needs a hard ceiling or it steals the
            // width the screenshot needs; stacked above it can run wider.
            .frame(maxWidth: placement.isHorizontal ? 560 : 1180,
                   alignment: placement.isHorizontal ? .leading : .center)
            .padding(.horizontal, placement.isHorizontal ? 0 : 60)
            // Sits the column below the content's top edge rather than flush
            // with it. Only meaningful beside the content; a stacked caption
            // has no edge to align against.
            .padding(.top, placement.isHorizontal ? captionTopInset : 0)
        }
    }

    @ViewBuilder private var framedContent: some View {
        if framed {
            content()
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.55), radius: 44, y: 26)
                .shadow(color: accent.opacity(0.18), radius: 60)
        } else {
            content()
        }
    }
}

/// The dark gradient `ShotCard` uses when no custom `background:` is supplied.
public struct ShotCardDefaultBackground: View {
    public init() {}

    public var body: some View {
        LinearGradient(
            colors: [Color(red: 0.06, green: 0.09, blue: 0.13), .black],
            startPoint: .top, endPoint: .bottom
        )
    }
}

public extension ShotCard where Background == ShotCardDefaultBackground, Detail == EmptyView {
    /// The common case: default dark gradient, no extra detail. Keeps
    /// `ShotCard("Title") { view }` and `ShotCard { view }` working.
    init(
        _ title: String? = nil,
        subtitle: String? = nil,
        eyebrow: String? = nil,
        eyebrowSymbol: String? = nil,
        accent: Color = .green,
        framed: Bool = true,
        placement: CaptionPlacement = .top,
        captionTopInset: CGFloat = 56,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            title,
            subtitle: subtitle,
            eyebrow: eyebrow,
            eyebrowSymbol: eyebrowSymbol,
            accent: accent,
            framed: framed,
            placement: placement,
            captionTopInset: captionTopInset,
            background: { ShotCardDefaultBackground() },
            detail: { EmptyView() },
            content: content
        )
    }
}

public extension ShotCard where Detail == EmptyView {
    /// Custom background, no extra detail.
    init(
        _ title: String? = nil,
        subtitle: String? = nil,
        eyebrow: String? = nil,
        eyebrowSymbol: String? = nil,
        accent: Color = .green,
        framed: Bool = true,
        placement: CaptionPlacement = .top,
        captionTopInset: CGFloat = 56,
        @ViewBuilder background: @escaping () -> Background,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            title,
            subtitle: subtitle,
            eyebrow: eyebrow,
            eyebrowSymbol: eyebrowSymbol,
            accent: accent,
            framed: framed,
            placement: placement,
            captionTopInset: captionTopInset,
            background: background,
            detail: { EmptyView() },
            content: content
        )
    }
}

public extension ShotCard where Background == ShotCardDefaultBackground {
    /// Default background with supporting detail beside or beneath the caption.
    init(
        _ title: String? = nil,
        subtitle: String? = nil,
        eyebrow: String? = nil,
        eyebrowSymbol: String? = nil,
        accent: Color = .green,
        framed: Bool = true,
        placement: CaptionPlacement = .top,
        captionTopInset: CGFloat = 56,
        @ViewBuilder detail: @escaping () -> Detail,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            title,
            subtitle: subtitle,
            eyebrow: eyebrow,
            eyebrowSymbol: eyebrowSymbol,
            accent: accent,
            framed: framed,
            placement: placement,
            captionTopInset: captionTopInset,
            background: { ShotCardDefaultBackground() },
            detail: detail,
            content: content
        )
    }
}

// MARK: - Device frame (iPhone mockup)

/// The top cutout style for `DeviceFrame`.
public enum DeviceCutout: Sendable {
    case notch          // classic iPhone notch (a tab from the top edge)
    case dynamicIsland  // floating pill
    case none
}

/// Wraps `content` in an iPhone device bezel with a notch (or Dynamic Island) and
/// an optional status bar, so a captured screen reads as a real phone shot instead
/// of a full-bleed image. Pure SwiftUI shapes — no image assets, so it stays crisp
/// at any scale.
///
/// Size the screen `content` yourself (e.g. `.frame(width: 393, height: 852)`);
/// `DeviceFrame` adds the bezel around it. Pair with `ShotCard(framed: false)` so
/// the card doesn't add its own Mac-window border on top:
///
/// ```swift
/// ShotCard("Order in seconds", subtitle: "Your usual, one tap away", framed: false) {
///     DeviceFrame { MyScreen().frame(width: 393, height: 852) }
/// }
/// ```
///
/// The status bar and cutout overlay the top of `content`, filling the safe area
/// that a captured app view leaves empty. Give your screen a little top padding so
/// its own content sits below them.
public struct DeviceFrame<Content: View>: View {
    public var screenCornerRadius: CGFloat
    public var bezelWidth: CGFloat
    public var bezelColor: Color
    public var cutout: DeviceCutout
    public var showsStatusBar: Bool
    public var statusBarTime: String
    /// Light (white) status-bar glyphs for dark content; false for light content.
    public var lightStatusBar: Bool
    public var showsSideButtons: Bool
    @ViewBuilder public var content: () -> Content

    public init(
        screenCornerRadius: CGFloat = 48,
        bezelWidth: CGFloat = 14,
        bezelColor: Color = Color(white: 0.04),
        cutout: DeviceCutout = .notch,
        showsStatusBar: Bool = true,
        statusBarTime: String = "9:41",
        lightStatusBar: Bool = true,
        showsSideButtons: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.screenCornerRadius = screenCornerRadius
        self.bezelWidth = bezelWidth
        self.bezelColor = bezelColor
        self.cutout = cutout
        self.showsStatusBar = showsStatusBar
        self.statusBarTime = statusBarTime
        self.lightStatusBar = lightStatusBar
        self.showsSideButtons = showsSideButtons
        self.content = content
    }

    private var deviceCornerRadius: CGFloat { screenCornerRadius + bezelWidth }

    public var body: some View {
        content()
            .overlay(alignment: .top) { if showsStatusBar { statusBar } }
            .overlay(alignment: .top) { cutoutShape }
            .clipShape(RoundedRectangle(cornerRadius: screenCornerRadius, style: .continuous))
            .padding(bezelWidth)
            .background(
                RoundedRectangle(cornerRadius: deviceCornerRadius, style: .continuous)
                    .fill(bezelColor)
            )
            .overlay(sideButtons)
            .overlay(
                RoundedRectangle(cornerRadius: deviceCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: screenCornerRadius, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.6), lineWidth: 1)
                    .padding(bezelWidth)
            )
            .shadow(color: .black.opacity(0.5), radius: 34, y: 18)
    }

    @ViewBuilder private var cutoutShape: some View {
        switch cutout {
        case .notch:
            UnevenRoundedRectangle(
                bottomLeadingRadius: 18, bottomTrailingRadius: 18, style: .continuous
            )
            .fill(.black)
            .frame(width: 160, height: 30)
        case .dynamicIsland:
            Capsule(style: .continuous)
                .fill(.black)
                .frame(width: 118, height: 35)
                .padding(.top, 11)
        case .none:
            EmptyView()
        }
    }

    private var statusBar: some View {
        let tint: Color = lightStatusBar ? .white : .black
        return HStack {
            Text(statusBarTime)
                .font(.system(size: 17, weight: .semibold))
            Spacer()
            HStack(spacing: 6) {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(0..<4, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .frame(width: 3, height: 5 + CGFloat(i) * 3)
                    }
                }
                Image(systemName: "wifi").font(.system(size: 15, weight: .semibold))
                Image(systemName: "battery.100").font(.system(size: 16, weight: .semibold))
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 30)
        .frame(height: 44)
    }

    @ViewBuilder private var sideButtons: some View {
        if showsSideButtons {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let t = max(3, bezelWidth * 0.42)   // button thickness
                let x = t / 2 - 0.5                  // sit flush on the metal edge

                // Left edge: action button, volume up, volume down.
                Capsule().fill(bezelColor)
                    .frame(width: t, height: h * 0.05)
                    .position(x: x, y: h * 0.205)
                Capsule().fill(bezelColor)
                    .frame(width: t, height: h * 0.085)
                    .position(x: x, y: h * 0.305)
                Capsule().fill(bezelColor)
                    .frame(width: t, height: h * 0.085)
                    .position(x: x, y: h * 0.415)

                // Right edge: side (power) button.
                Capsule().fill(bezelColor)
                    .frame(width: t, height: h * 0.12)
                    .position(x: w - x, y: h * 0.30)
            }
        }
    }
}
