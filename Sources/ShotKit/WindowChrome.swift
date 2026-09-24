import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Wraps content in a macOS window frame: title bar, traffic lights, and an
/// optional title.
/// This is decorative SwiftUI chrome, not an AppKit title bar. For a faithful
/// `NavigationSplitView` window, use `ShotKit.captureWindow` and compose the
/// resulting `WindowSnapshot` without this wrapper.
///
/// `ShotCard`'s own `framed:` styling gives content a rounded border, which
/// suits a popover. A Settings or History window wants the real thing, so a
/// captured window reads as a window rather than as a floating panel.
///
/// ```swift
/// ShotCard("See your usage over time") {
///     WindowChrome(title: "MyApp — History") {
///         HistoryView(model: .demo)
///     }
/// }
/// ```
///
/// Pair with `ShotCard(framed: false)` so the card does not add a second border
/// around this one.
public struct WindowChrome<Content: View>: View {
    public var title: String?
    public var titleBarHeight: CGFloat
    public var cornerRadius: CGFloat
    /// Title bar fill. Defaults to a dark bar; pass a lighter one for a light
    /// appearance capture.
    public var barColor: Color
    /// Fills the area below the title bar. Without it, any gap between the
    /// frame and the hosted view shows whatever is behind the card, which reads
    /// as bands down the sides; real windows always have a background.
    public var contentBackground: Color
    public var showsTrafficLights: Bool
    @ViewBuilder public var content: () -> Content

    public init(
        title: String? = nil,
        titleBarHeight: CGFloat = 38,
        cornerRadius: CGFloat = 12,
        barColor: Color = Color(white: 0.16),
        contentBackground: Color = .shotWindowBackground,
        showsTrafficLights: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.titleBarHeight = titleBarHeight
        self.cornerRadius = cornerRadius
        self.barColor = barColor
        self.contentBackground = contentBackground
        self.showsTrafficLights = showsTrafficLights
        self.content = content
    }

    public var body: some View {
        VStack(spacing: 0) {
            titleBar
            content()
                .background(contentBackground)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 40, y: 22)
    }

    private var titleBar: some View {
        // Title only in the layout; the lights ride in an overlay and the fill
        // in a background. A greedy child here (an HStack with a Spacer, say)
        // would make the whole frame wider than the window it is framing, which
        // shows up as bands down either side of the content.
        // Height only. Anything that wants width here — a Spacer, a greedy
        // frame, generous horizontal padding — sizes the whole window frame
        // rather than the view it is framing, and the surplus shows as bands
        // down the sides. The bar takes its width from the content instead, via
        // the enclosing VStack.
        Text(title ?? "")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.75))
            .lineLimit(1)
            .frame(height: titleBarHeight)
            .frame(maxWidth: .infinity)
            .background(barColor)
            .overlay(alignment: .leading) {
                if showsTrafficLights {
                    HStack(spacing: 8) {
                        TrafficLight(color: Color(red: 1.00, green: 0.37, blue: 0.34))
                        TrafficLight(color: Color(red: 1.00, green: 0.74, blue: 0.19))
                        TrafficLight(color: Color(red: 0.16, green: 0.79, blue: 0.25))
                    }
                    .padding(.leading, 14)
                }
            }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.black.opacity(0.35))
                .frame(height: 1)
        }
    }
}

private struct TrafficLight: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
            .overlay(Circle().strokeBorder(.black.opacity(0.18), lineWidth: 0.5))
    }
}

public extension Color {
    /// The platform's window background.
    ///
    /// Exists because `Color(nsColor:)` is macOS-only, and naming it directly in
    /// a default argument breaks this file's iOS build — the file has no
    /// platform guard, since everything else in it is plain SwiftUI. Swift
    /// Package Index compiles every target for every platform the package
    /// declares, so one unguarded AppKit reference fails its iOS compatibility
    /// build even though the type is only ever used on a Mac.
    static var shotWindowBackground: Color {
        #if canImport(AppKit)
        Color(nsColor: .windowBackgroundColor)
        #elseif canImport(UIKit)
        Color(uiColor: .systemBackground)
        #else
        Color.gray
        #endif
    }
}
