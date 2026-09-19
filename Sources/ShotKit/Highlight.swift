import SwiftUI

/// Draws attention to one control inside a captured view, optionally with a
/// note explaining it.
///
/// Applied as a modifier so the highlighted view stays exactly where it is in
/// the real layout. Nothing is repositioned, which matters: a marketing shot
/// that rearranges the UI to make room for an annotation is no longer showing
/// the app.
///
/// ```swift
/// SettingsRow()
///     .shotHighlight("Switch providers here", edge: .trailing)
/// ```
/// Whether the note sits beyond the highlighted view or tucks in against it.
///
/// `.outside` reads best on open canvas. `.inside` exists because containers
/// that clip — a window frame, a scroll view, any `clipShape` — will cut off a
/// note that extends past their bounds.
public enum HighlightNotePlacement: Sendable {
    case outside
    case inside
}

public struct HighlightStyle: Sendable {
    public var notePlacement: HighlightNotePlacement
    public var color: Color
    public var lineWidth: CGFloat
    public var cornerRadius: CGFloat
    /// Padding between the view's bounds and the ring, so the ring does not
    /// crowd the control it is pointing at.
    public var inset: CGFloat
    /// Tint laid over the highlighted view. Keep this very low; it is a hint,
    /// not a spotlight.
    public var fillOpacity: Double

    public init(
        color: Color = .green,
        lineWidth: CGFloat = 3,
        cornerRadius: CGFloat = 10,
        inset: CGFloat = 5,
        fillOpacity: Double = 0.10,
        notePlacement: HighlightNotePlacement = .outside
    ) {
        self.notePlacement = notePlacement
        self.color = color
        self.lineWidth = lineWidth
        self.cornerRadius = cornerRadius
        self.inset = inset
        self.fillOpacity = fillOpacity
    }

    public static let `default` = HighlightStyle()
}

/// Which side of the highlighted view a note sits on.
public enum HighlightNoteEdge: Sendable {
    case top, bottom, leading, trailing
}

public extension View {
    /// Rings this view to draw the eye, with an optional note beside it.
    ///
    /// The ring is drawn in an overlay and the note in another, so neither
    /// affects layout and the surrounding UI is captured untouched.
    func shotHighlight(
        _ note: String? = nil,
        edge: HighlightNoteEdge = .trailing,
        style: HighlightStyle = .default
    ) -> some View {
        modifier(HighlightModifier(note: note, edge: edge, style: style))
    }
}

private struct HighlightModifier: ViewModifier {
    let note: String?
    let edge: HighlightNoteEdge
    let style: HighlightStyle

    func body(content: Content) -> some View {
        content
            .overlay(ring)
            .overlay(alignment: alignment) { noteLabel }
    }

    private var ring: some View {
        RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
            .inset(by: -style.inset)
            .fill(style.color.opacity(style.fillOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                    .inset(by: -style.inset)
                    .strokeBorder(style.color, lineWidth: style.lineWidth)
            )
    }

    @ViewBuilder private var noteLabel: some View {
        if let note {
            Text(note)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(style.color, in: Capsule())
                .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                .fixedSize()
                .offset(offset)
        }
    }

    private var alignment: Alignment {
        switch edge {
        case .top: return .top
        case .bottom: return .bottom
        case .leading: return .leading
        case .trailing: return .trailing
        }
    }

    /// Outside: pushed clear of the ring, so it never covers the control it
    /// describes. Inside: tucked against the edge, for containers that clip.
    private var offset: CGSize {
        switch style.notePlacement {
        case .outside:
            let gap = style.inset + 14
            switch edge {
            case .top: return CGSize(width: 0, height: -(gap + 22))
            case .bottom: return CGSize(width: 0, height: gap + 22)
            case .leading: return CGSize(width: -gap, height: 0)
            case .trailing: return CGSize(width: gap, height: 0)
            }
        case .inside:
            let inset: CGFloat = 10
            switch edge {
            case .top: return CGSize(width: 0, height: inset)
            case .bottom: return CGSize(width: 0, height: -inset)
            case .leading: return CGSize(width: inset, height: 0)
            case .trailing: return CGSize(width: -inset, height: 0)
            }
        }
    }
}
