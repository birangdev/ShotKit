import SwiftUI

// MARK: - Callouts
//
// `shotHighlight` puts a note beside the control it rings. That works when the
// control has slack around it, and fails when it does not: a 16pt icon in a
// narrow popover has nowhere to put a label, and a container that clips will cut
// off anything that reaches past its bounds.
//
// A callout separates the two halves. The control is only *marked*, inside the
// container; the ring, the leader line, and the note are drawn by an overlay
// applied outside the container, where there is room. SwiftUI's anchor
// preferences carry the control's frame across that gap.
//
// ```swift
// ShotCard("Pin what matters") {
//     MenuPopover()
//         .clipShape(RoundedRectangle(cornerRadius: 14))
//         .shotCallouts([
//             ShotCallout("pin", "Pin a provider", detail: "Keeps it in the menu bar.")
//         ])
// }
// ```
//
// Ordering matters twice over. Put `.shotCallouts` *outside* the clip, or the
// note is clipped along with everything else. Keep it *inside* `ShotCard`'s
// content, though: the card auto-scales what it is given, and a callout applied
// over the finished card resolves its anchors in the unscaled layout, so the
// ring lands away from the control it is meant to be ringing.

/// Publishes the frames of marked controls up to the nearest `shotCallouts`.
public struct ShotCalloutAnchorKey: PreferenceKey {
    public static var defaultValue: [String: Anchor<CGRect>] { [:] }

    public static func reduce(
        value: inout [String: Anchor<CGRect>],
        nextValue: () -> [String: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

public extension View {
    /// Marks this view as the target of a `ShotCallout` with the same id.
    ///
    /// Publishes the view's frame and draws nothing, so it cannot disturb the
    /// layout being captured. A target with no matching callout is ignored.
    func shotCalloutTarget(_ id: String) -> some View {
        anchorPreference(key: ShotCalloutAnchorKey.self, value: .bounds) { [id: $0] }
    }
}

/// Where a callout's note sits relative to the control it points at.
public enum ShotCalloutSide: Sendable {
    case top, bottom, leading, trailing
}

/// One annotation: a ring on a marked control, a leader line, and a note.
public struct ShotCallout: Identifiable, Sendable {
    /// Matches the id passed to `shotCalloutTarget`.
    public let id: String
    public var title: String
    /// Optional second line, for when the title alone does not explain it.
    public var detail: String?
    public var side: ShotCalloutSide
    /// Length of the leader line, in points, before the note begins.
    public var leader: CGFloat
    /// Ring outline. Use `.circle` for round icon buttons and status dots.
    public var shape: HighlightShape
    /// Overrides the style's colour for this one callout.
    public var color: Color?

    public init(
        _ id: String,
        _ title: String,
        detail: String? = nil,
        side: ShotCalloutSide = .trailing,
        leader: CGFloat = 64,
        shape: HighlightShape = .roundedRectangle,
        color: Color? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.side = side
        self.leader = leader
        self.shape = shape
        self.color = color
    }
}

public struct ShotCalloutStyle: Sendable {
    public var color: Color
    public var lineWidth: CGFloat
    /// Gap between the control's bounds and the ring.
    public var ringInset: CGFloat
    /// Whether the ring sits outside the control's bounds or within them. A
    /// control that spans its container — a full-width row — needs `.contained`,
    /// or the ring reaches past the container's frame and reads as a mistake.
    public var fit: HighlightRingFit
    public var cornerRadius: CGFloat
    /// Ceiling on note width, so a long explanation wraps instead of stretching
    /// across the canvas.
    public var noteMaxWidth: CGFloat

    public init(
        color: Color = .yellow,
        lineWidth: CGFloat = 3,
        ringInset: CGFloat = 6,
        cornerRadius: CGFloat = 8,
        noteMaxWidth: CGFloat = 260,
        fit: HighlightRingFit = .surrounding
    ) {
        self.color = color
        self.lineWidth = lineWidth
        self.ringInset = ringInset
        self.cornerRadius = cornerRadius
        self.noteMaxWidth = noteMaxWidth
        self.fit = fit
    }

    public static let `default` = ShotCalloutStyle()
}

public extension View {
    /// Draws a callout for every marked target inside this view.
    ///
    /// Apply this *outside* any container that clips, so notes can sit beyond
    /// the container while still pointing into it.
    func shotCallouts(
        _ callouts: [ShotCallout],
        style: ShotCalloutStyle = .default
    ) -> some View {
        overlayPreferenceValue(ShotCalloutAnchorKey.self) { anchors in
            GeometryReader { proxy in
                ForEach(callouts) { callout in
                    if let anchor = anchors[callout.id] {
                        ShotCalloutLayer(
                            callout: callout,
                            style: style,
                            target: proxy[anchor],
                            canvas: proxy.size
                        )
                    }
                }
            }
            // Annotations never take hit-testing or layout from the shot.
            .allowsHitTesting(false)
        }
    }
}

/// One callout's ring, leader line, and note, positioned in the overlay's space.
///
/// Everything is placed against an explicitly sized, top-leading container.
/// `position` and `alignmentGuide` both resolve against whatever size the
/// enclosing stack happened to take, which is not the canvas once a fixed-size
/// note is in the stack — the ring then drifts away from the control it rings.
private struct ShotCalloutLayer: View {
    let callout: ShotCallout
    let style: ShotCalloutStyle
    let target: CGRect
    let canvas: CGSize

    private var color: Color { callout.color ?? style.color }

    /// The ring's rect: the control's frame, opened up by the inset — or closed
    /// in by it, plus half the stroke, when the ring must stay inside bounds.
    private var ringRect: CGRect {
        switch style.fit {
        case .surrounding:
            return target.insetBy(dx: -style.ringInset, dy: -style.ringInset)
        case .contained:
            let inset = style.ringInset + style.lineWidth / 2
            return target.insetBy(dx: inset, dy: inset)
        }
    }

    /// Where the leader line leaves the ring.
    private var anchorPoint: CGPoint {
        switch callout.side {
        case .top: return CGPoint(x: ringRect.midX, y: ringRect.minY)
        case .bottom: return CGPoint(x: ringRect.midX, y: ringRect.maxY)
        case .leading: return CGPoint(x: ringRect.minX, y: ringRect.midY)
        case .trailing: return CGPoint(x: ringRect.maxX, y: ringRect.midY)
        }
    }

    /// Where the leader line ends and the note begins.
    private var notePoint: CGPoint {
        switch callout.side {
        case .top: return CGPoint(x: anchorPoint.x, y: anchorPoint.y - callout.leader)
        case .bottom: return CGPoint(x: anchorPoint.x, y: anchorPoint.y + callout.leader)
        case .leading: return CGPoint(x: anchorPoint.x - callout.leader, y: anchorPoint.y)
        case .trailing: return CGPoint(x: anchorPoint.x + callout.leader, y: anchorPoint.y)
        }
    }

    /// Anchoring the note to the container corner nearest its own side is what
    /// lets it be placed without knowing its height: only `.top` needs to grow
    /// upwards, and that is exactly what a bottom-anchored container gives.
    private var noteAnchor: Alignment {
        callout.side == .top ? .bottomLeading : .topLeading
    }

    /// Offset from `noteAnchor` to the note's own corner. Depends on the note's
    /// width, which is fixed by the style, and never on its height.
    private var noteOffset: CGSize {
        let width = style.noteMaxWidth
        switch callout.side {
        // Centred under or over the control, then kept within the container's
        // width. For a vertical side the horizontal position is incidental, so
        // a control near an edge would otherwise push its note off the canvas.
        // For `.leading`/`.trailing` the horizontal position *is* the point, so
        // those are never clamped.
        case .bottom:
            return CGSize(width: centredX(width: width), height: notePoint.y)
        case .top:
            return CGSize(width: centredX(width: width), height: notePoint.y - canvas.height)
        case .trailing:
            return CGSize(width: notePoint.x, height: ringRect.minY)
        case .leading:
            return CGSize(width: notePoint.x - width, height: ringRect.minY)
        }
    }

    private func centredX(width: CGFloat) -> CGFloat {
        let centred = notePoint.x - width / 2
        guard canvas.width > width else { return centred }
        return min(max(centred, 0), canvas.width - width)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Pins the stack to the canvas, so the strokes below resolve their
            // path in the same space the anchor was measured in.
            Color.clear

            CalloutStrokes(
                ringRect: ringRect,
                kind: callout.shape,
                cornerRadius: style.cornerRadius,
                from: anchorPoint,
                to: notePoint
            )
            .stroke(color, style: StrokeStyle(lineWidth: style.lineWidth, lineCap: .round))
            .frame(width: canvas.width, height: canvas.height)
        }
        .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
        .overlay(alignment: noteAnchor) {
            note.offset(x: noteOffset.width, y: noteOffset.height)
        }
    }

    private var note: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(callout.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.black)
            if let detail = callout.detail {
                Text(detail)
                    .font(.system(size: 14))
                    .foregroundStyle(.black.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        // Fixed, not maximum: the placement above is computed from this width,
        // so it has to be the width the note actually takes.
        .frame(width: style.noteMaxWidth, alignment: .leading)
        .background(color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }
}

/// Ring and leader line as one path, so both stroke identically and neither can
/// drift from the other.
private struct CalloutStrokes: Shape {
    let ringRect: CGRect
    let kind: HighlightShape
    let cornerRadius: CGFloat
    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = kind.path(in: ringRect, cornerRadius: cornerRadius)
        path.move(to: from)
        path.addLine(to: to)
        return path
    }
}
