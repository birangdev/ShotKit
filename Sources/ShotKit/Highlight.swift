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
///
/// For a control too small or too hemmed-in to carry a note beside it, use
/// ``SwiftUI/View/shotCalloutTarget(_:)`` instead: that draws the note outside
/// the clipping container with a leader line back to the control.

/// Whether the note sits beyond the highlighted view or tucks in against it.
///
/// `.outside` reads best on open canvas. `.inside` exists because containers
/// that clip — a window frame, a scroll view, any `clipShape` — will cut off a
/// note that extends past their bounds.
public enum HighlightNotePlacement: Sendable {
    case outside
    case inside
}

/// Whether the ring sits outside the highlighted view's bounds or within them.
public enum HighlightRingFit: Sendable {
    /// Ring drawn outside the bounds, giving the control breathing room. Right
    /// for a control with slack around it.
    case surrounding

    /// Ring drawn entirely within the bounds, stroke included.
    ///
    /// Use when the view reaches the edge of a clipping container — a full-width
    /// list row, a control against a window frame. A surrounding ring there is
    /// clipped by the container or spills past its rounded corner, so the
    /// highlight reads as a rendering fault rather than as an annotation.
    case contained
}

/// The outline drawn around a highlighted control.
public enum HighlightShape: Sendable {
    case roundedRectangle
    /// For circular controls — a status dot, an icon-only button.
    case circle
    /// For pill-shaped controls — a tag, a segmented control.
    case capsule

    func path(in rect: CGRect, cornerRadius: CGFloat) -> Path {
        switch self {
        case .roundedRectangle:
            return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: rect)
        case .circle:
            return Circle().path(in: rect)
        case .capsule:
            return Capsule(style: .continuous).path(in: rect)
        }
    }
}

/// A shape erased to whichever `HighlightShape` was chosen. `AnyShape` would do
/// this too, but it is not `InsettableShape`, and the ring needs a plain `Shape`
/// only — inset is handled by padding so the stroke can be kept inside bounds.
struct HighlightRingShape: Shape {
    let kind: HighlightShape
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        kind.path(in: rect, cornerRadius: cornerRadius)
    }
}

public struct HighlightStyle: Sendable {
    public var notePlacement: HighlightNotePlacement
    public var fit: HighlightRingFit
    public var shape: HighlightShape
    public var color: Color
    public var lineWidth: CGFloat
    public var cornerRadius: CGFloat
    /// Distance between the view's bounds and the ring. Outward for
    /// `.surrounding`, inward for `.contained`.
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
        notePlacement: HighlightNotePlacement = .outside,
        fit: HighlightRingFit = .surrounding,
        shape: HighlightShape = .roundedRectangle
    ) {
        self.notePlacement = notePlacement
        self.fit = fit
        self.shape = shape
        self.color = color
        self.lineWidth = lineWidth
        self.cornerRadius = cornerRadius
        self.inset = inset
        self.fillOpacity = fillOpacity
    }

    public static let `default` = HighlightStyle()

    /// Ring and note both kept within the highlighted view's bounds. The safe
    /// choice inside a window, a popover, or any container that clips.
    public static let withinBounds = HighlightStyle(
        notePlacement: .inside,
        fit: .contained
    )

    /// How far the ring's own drawing extends past the view's bounds.
    /// Negative for `.contained`, which draws inward.
    var ringPadding: CGFloat {
        switch fit {
        case .surrounding:
            return -inset
        case .contained:
            // Half the stroke sits either side of the path, so the extra half
            // line width is what actually keeps the ring inside the bounds.
            return inset + lineWidth / 2
        }
    }
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
        let shape = HighlightRingShape(kind: style.shape, cornerRadius: style.cornerRadius)
        return shape
            .fill(style.color.opacity(style.fillOpacity))
            .overlay(shape.stroke(style.color, lineWidth: style.lineWidth))
            .padding(style.ringPadding)
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
            let gap = max(style.inset, 0) + 14
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
