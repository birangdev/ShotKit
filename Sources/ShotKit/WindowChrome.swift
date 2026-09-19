import SwiftUI

/// Wraps content in a macOS window frame: title bar, traffic lights, and an
/// optional title.
///
/// `ShotCard`'s own `framed:` styling gives content a rounded border, which
/// suits a popover. A Settings or History window wants the real thing, so a
/// captured window reads as a window rather than as a floating panel.
///
/// ```swift
/// ShotCard("See your usage over time") {
///     WindowChrome(title: "StackGauge — History") {
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
    public var showsTrafficLights: Bool
    @ViewBuilder public var content: () -> Content

    public init(
        title: String? = nil,
        titleBarHeight: CGFloat = 38,
        cornerRadius: CGFloat = 12,
        barColor: Color = Color(white: 0.16),
        showsTrafficLights: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.titleBarHeight = titleBarHeight
        self.cornerRadius = cornerRadius
        self.barColor = barColor
        self.showsTrafficLights = showsTrafficLights
        self.content = content
    }

    public var body: some View {
        VStack(spacing: 0) {
            titleBar
            content()
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 40, y: 22)
    }

    private var titleBar: some View {
        ZStack {
            barColor

            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }

            if showsTrafficLights {
                HStack(spacing: 8) {
                    TrafficLight(color: Color(red: 1.00, green: 0.37, blue: 0.34))
                    TrafficLight(color: Color(red: 1.00, green: 0.74, blue: 0.19))
                    TrafficLight(color: Color(red: 0.16, green: 0.79, blue: 0.25))
                    Spacer()
                }
                .padding(.leading, 14)
            }
        }
        .frame(height: titleBarHeight)
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
