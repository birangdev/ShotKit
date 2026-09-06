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
    public static func capturePNG(_ scene: ScreenshotScene) -> Data? {
        let spec = scene.spec
        let content = AnyView(
            scene.makeContent()
                .frame(width: spec.pointSize.width, height: spec.pointSize.height)
                .environment(\.colorScheme, .dark)
        )
        return rasterize(content, spec: spec)
    }

    /// Captures every scene and writes `<name>.png` into `folder`. Returns the
    /// URLs written. Creates the folder if needed.
    @MainActor
    @discardableResult
    public static func export(_ scenes: [ScreenshotScene], to folder: URL) -> [URL] {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var written: [URL] = []
        for scene in scenes {
            guard let data = capturePNG(scene) else { continue }
            let url = folder.appendingPathComponent("\(scene.spec.name).png")
            if (try? data.write(to: url)) != nil { written.append(url) }
        }
        return written
    }

    #if canImport(AppKit)
    /// macOS: host in a borderless `NSWindow`, then `cacheDisplay` the hierarchy.
    @MainActor
    private static func rasterize(_ content: AnyView, spec: ScreenshotSpec) -> Data? {
        let hosting = NSHostingView(rootView: content)
        hosting.frame = CGRect(origin: .zero, size: spec.pointSize)

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        // Must be on-screen for SwiftUI/Charts to lay out and draw; a borderless
        // window that we order out immediately after keeps the flash minimal.
        window.orderFrontRegardless()

        // Give SwiftUI, Charts, and AppKit controls a few run-loop passes to lay
        // out and render before we snapshot the hierarchy.
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        let bounds = hosting.bounds
        defer { window.orderOut(nil) }
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        hosting.cacheDisplay(in: bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
    #elseif canImport(UIKit)
    /// iOS: host in a `UIWindow` attached to the active scene, then snapshot the
    /// live hierarchy with `drawHierarchy` at the spec's scale.
    @MainActor
    private static func rasterize(_ content: AnyView, spec: ScreenshotSpec) -> Data? {
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
    private static func rasterize(_ content: AnyView, spec: ScreenshotSpec) -> Data? { nil }
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

/// A marketing "card": gradient background, an optional big headline, and the
/// app view centered on it with a rounded window frame and shadow.
///
/// Pass `title: nil` (and `subtitle: nil`) to omit the caption entirely — you
/// still get the framed, auto-fit shot, just without any text over it.
///
/// The whole column (caption + framed window) is auto-scaled to fit the canvas
/// via `ViewThatFits`, which picks the largest candidate scale whose reserved
/// size (see `ScaledContent`) actually fits. That keeps a compact view large and
/// prominent while a much taller window shrinks just enough to be captured
/// whole — no per-scene tuning, and nothing clips.
public struct ShotCard<Background: View, Content: View>: View {
    public let title: String?
    public let subtitle: String?
    public let accent: Color
    /// When true (default) the content gets a rounded "window" frame + border +
    /// shadow (right for a Mac window). Set false when the content supplies its
    /// own shape — e.g. a `DeviceFrame` iPhone mockup — so it isn't double-framed.
    public let framed: Bool
    @ViewBuilder public let background: () -> Background
    @ViewBuilder public let content: () -> Content

    public init(
        _ title: String? = nil,
        subtitle: String? = nil,
        accent: Color = .green,
        framed: Bool = true,
        @ViewBuilder background: @escaping () -> Background,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accent = accent
        self.framed = framed
        self.background = background
        self.content = content
    }

    private var hasCaption: Bool { title != nil || subtitle != nil }

    public var body: some View {
        ZStack {
            background()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Candidate scales, largest first. `ViewThatFits` renders the first
            // whose (accurately reserved) size fits vertically. A compact view
            // lands near the top of the range; tall windows drop to a smaller
            // step automatically. Listed explicitly rather than via `ForEach` so
            // each is treated as its own fit candidate.
            ViewThatFits(in: .vertical) {
                column(scale: 1.3)
                column(scale: 1.15)
                column(scale: 1.0)
                column(scale: 0.9)
                column(scale: 0.8)
                column(scale: 0.72)
                column(scale: 0.64)
                column(scale: 0.56)
                column(scale: 0.48)
                column(scale: 0.4)
            }
        }
    }

    private func column(scale: CGFloat) -> some View {
        ScaledContent(scale: scale) {
            VStack(spacing: 44) {
                if hasCaption {
                    VStack(spacing: 12) {
                        if let title {
                            Text(title)
                                .font(.system(size: 54, weight: .bold, design: .rounded))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white)
                        }
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 25, weight: .regular))
                                .foregroundStyle(.white.opacity(0.65))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: 1180)
                    .padding(.horizontal, 60)
                }

                framedContent
            }
        }
        // Constant margin (outside the scale) so the fitted column always keeps
        // breathing room against the canvas edges.
        .padding(56)
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

public extension ShotCard where Background == ShotCardDefaultBackground {
    /// Convenience initializer that uses the default dark gradient background, so
    /// `ShotCard("Title") { view }` and `ShotCard { view }` work without passing
    /// a `background:`.
    init(
        _ title: String? = nil,
        subtitle: String? = nil,
        accent: Color = .green,
        framed: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            title,
            subtitle: subtitle,
            accent: accent,
            framed: framed,
            background: { ShotCardDefaultBackground() },
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
