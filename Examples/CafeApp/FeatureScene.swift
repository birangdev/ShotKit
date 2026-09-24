import ShotKit
import SwiftUI

// MARK: - The 1.1 composition, end to end
//
// One scene exercising caption placement, `WindowChrome`, `MenuBarFrame` and
// `shotHighlight` together: copy and a feature list down one side, a framed
// window down the other, with one control ringed and annotated.

/// A feature bullet for the caption's detail slot.
struct CafeFeature: Identifiable {
    let id = UUID()
    let symbol: String
    let title: String
    let blurb: String
}

struct CafeFeatureList: View {
    let features: [CafeFeature]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(features) { feature in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: feature.symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(CafePalette.icon)
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(feature.title)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(feature.blurb)
                            .font(.system(size: 15))
                            .foregroundStyle(.white.opacity(0.62))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// A stand-in for a desktop window's contents.
struct CafeOrdersWindow: View {
    /// Row to ring with `shotHighlight`, if any.
    var highlighting: Int?
    /// Colour of that ring. Matching it to whatever explains the row is what
    /// makes the two read as one thing rather than as two decorations.
    var highlightColor: Color = CafePalette.icon
    /// Note carried by the ring. Nil when something outside the window is
    /// already doing the explaining.
    var highlightNote: String? = "Most ordered"
    /// Row to mark as a callout target, if any. The ring and note for it are
    /// drawn by whoever applies `shotCallouts` further out.
    var calloutTarget: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(CafeMock.coffee.types.enumerated()), id: \.element.id) { index, type in
                HStack(spacing: 14) {
                    // An empty disc reads as a missing image. The same icon the
                    // iOS scenes use makes the row look like a real row.
                    ZStack {
                        Circle().fill(CafePalette.icon).frame(width: 30, height: 30)
                        Image(systemName: coffeeIcon(type.name))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color(red: 0.25, green: 0.14, blue: 0.05))
                    }
                    Text(type.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(4 + index * 3) today")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.55))
                        .monospacedDigit()
                }
                .padding(.horizontal, 22)
                .frame(height: 62)
                // The point of the highlight: ring one real row in place,
                // without moving anything around it.
                .modifier(HighlightIf(
                    active: index == highlighting,
                    note: highlightNote,
                    color: highlightColor
                ))
                .modifier(CalloutTargetIf(active: index == calloutTarget, id: "drink-row"))

                if index < CafeMock.coffee.types.count - 1 {
                    Divider().overlay(.white.opacity(0.08)).padding(.leading, 22)
                }
            }
        }
        .padding(.vertical, 12)
        .frame(width: 460)
        .background(Color(red: 0.11, green: 0.08, blue: 0.06))
    }
}

/// Marks one row, since `shotCalloutTarget` is unconditional like the highlight.
private struct CalloutTargetIf: ViewModifier {
    let active: Bool
    let id: String

    func body(content: Content) -> some View {
        if active {
            content.shotCalloutTarget(id)
        } else {
            content
        }
    }
}

/// Applies `shotHighlight` to one row only, since the modifier is unconditional.
private struct HighlightIf: ViewModifier {
    let active: Bool
    let note: String?
    var color: Color = CafePalette.icon

    func body(content: Content) -> some View {
        if active {
            // The row runs the full width of the window, so both the ring and
            // the note have to stay within its bounds: a surrounding ring is
            // sliced off by the window frame at either end.
            content.shotHighlight(
                note,
                edge: .trailing,
                style: HighlightStyle(color: color, cornerRadius: 8,
                                      notePlacement: .inside, fit: .contained)
            )
        } else {
            content
        }
    }
}

/// Caption on the trailing edge, window chrome around the content.
struct FeatureScene: ScreenshotScene {
    var spec: ScreenshotSpec {
        ScreenshotSpec("05-features", pointSize: AppStoreSize.macPoints, scale: 2)
    }

    @MainActor
    func makeContent() -> AnyView {
        AnyView(
            ShotCard(
                "Know what sells",
                subtitle: "Every order, counted as it happens.",
                accent: .orange,
                framed: false,
                placement: .trailing,
                background: { cafeMarketingBackground },
                detail: {
                    CafeFeatureList(features: [
                        CafeFeature(symbol: "chart.bar.fill", title: "Live counts",
                                    blurb: "Totals update the moment an order lands."),
                        CafeFeature(symbol: "clock.fill", title: "Busiest hours",
                                    blurb: "See when your queue actually forms."),
                        CafeFeature(symbol: "square.and.arrow.up", title: "Export anything",
                                    blurb: "Take the numbers wherever you need them.")
                    ])
                }
            ) {
                WindowChrome(title: "CafeApp — Orders") {
                    // One annotation, not two. A ring on a row plus a second
                    // ring on an icon inside another row just reads as clutter.
                    CafeOrdersWindow(calloutTarget: 0)
                }
                // Outside the window's clip so the note can sit beyond the
                // frame, but still inside the card's scaled content so the
                // annotation scales with the shot it points at.
                .shotCallouts(
                    [
                        ShotCallout(
                            "drink-row",
                            "Tap to reorder",
                            detail: "Every drink keeps its own running total for the day.",
                            // Upwards, into open canvas. Pointing down from the
                            // first row drags the leader line straight through
                            // the rows beneath it, which cuts the list in half.
                            side: .top,
                            leader: 70
                        )
                    ],
                    // The row spans the window, so the ring has to sit inside it.
                    style: ShotCalloutStyle(cornerRadius: 10, fit: .contained)
                )
            }
        )
    }
}

/// The menu-bar treatment: the popover shown hanging from a real menu bar.
struct MenuBarScene: ScreenshotScene {
    var spec: ScreenshotSpec {
        ScreenshotSpec("06-menubar", pointSize: AppStoreSize.macPoints, scale: 2)
    }

    @MainActor
    func makeContent() -> AnyView {
        AnyView(
            ShotCard(
                "Always one click away",
                subtitle: "Your café, from the menu bar.",
                accent: .orange,
                framed: false,
                background: { cafeMarketingBackground }
            ) {
                // A menu bar floating on the card reads as a graphic. Putting
                // it on a screen with a wallpaper behind it is what makes the
                // shot read as something captured from a Mac.
                DesktopFrame(
                    // Shallow on purpose: a full-height desktop leaves most of
                    // the shot as empty wallpaper below the popover.
                    screenSize: CGSize(width: 1180, height: 620),
                    bezelWidth: 0,
                    wallpaper: { cafeDesktopWallpaper },
                    content: {
                        MenuBarFrame(statusText: "12 ☕") {
                            // No ring here either: this shot is about where the
                            // popover lives, and an annotation on a row competes
                            // with that rather than adding to it.
                            CafeOrdersWindow()
                        }
                    }
                )
            }
        )
    }
}

/// Wallpaper for the desktop shot. Drawn rather than bundled: a real macOS
/// wallpaper cannot be redistributed with the package.
///
/// Deliberately cool against the card's warm mocha. A brown desktop on a brown
/// card blends into it, and the screen stops reading as a separate surface —
/// which is the one thing this frame exists to convey.
private var cafeDesktopWallpaper: some View {
    ZStack {
        LinearGradient(
            colors: [
                Color(red: 0.24, green: 0.20, blue: 0.42),
                Color(red: 0.09, green: 0.08, blue: 0.16)
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        // A dawn glow behind the status item, so the eye lands where the menu
        // bar is rather than on the empty middle of the desktop.
        RadialGradient(
            colors: [
                Color(red: 0.95, green: 0.70, blue: 0.42).opacity(0.55),
                .clear
            ],
            center: UnitPoint(x: 0.68, y: 0.05),
            startRadius: 0, endRadius: 560
        )
        RadialGradient(
            colors: [Color(red: 0.35, green: 0.55, blue: 0.85).opacity(0.35), .clear],
            center: UnitPoint(x: 0.12, y: 0.85),
            startRadius: 0, endRadius: 480
        )
    }
}


// MARK: - Highlight + explanation, side by side
//
// The caption stays on top and the body becomes two columns: what the row is on
// the left, the row itself ringed on the right. No new `CaptionPlacement` is
// needed — `ShotCard` takes any view as its content, so the two columns are just
// the content.

/// Ties the ringed row to the panel describing it. Deliberately not the yellow
/// the callouts use: an annotation pointing *at* something and a panel
/// *explaining* it are different jobs, and sharing a colour would imply they are
/// the same one.
private let selectionAccent = Color(red: 0.38, green: 0.82, blue: 0.74)

struct DrinkDetailScene: ScreenshotScene {
    var spec: ScreenshotSpec {
        ScreenshotSpec("07-selection", pointSize: AppStoreSize.macPoints, scale: 2)
    }

    @MainActor
    func makeContent() -> AnyView {
        AnyView(
            ShotCard(
                "Know every pour",
                subtitle: "Pick a drink to see exactly how it is made.",
                accent: selectionAccent,
                framed: false,
                background: { cafeMarketingBackground }
            ) {
                HStack(alignment: .top, spacing: 56) {
                    DrinkDetailPanel(accent: selectionAccent)
                    WindowChrome(title: "CafeApp — Orders") {
                        // Ringed, unlabelled: the panel beside it carries the
                        // explanation, so a note here would say it twice.
                        CafeOrdersWindow(
                            highlighting: 0,
                            highlightColor: selectionAccent,
                            highlightNote: nil
                        )
                    }
                }
            }
        )
    }
}

/// The left column: what the highlighted row actually is.
private struct DrinkDetailPanel: View {
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("SELECTED")
                .font(.system(size: 13, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(accent)

            Text("Ristretto")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("The short pull. Half the water of an espresso, so the sugars come through before the bitterness has a chance to.")
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.66))
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                DrinkStat(label: "Poured today", value: "4")
                statDivider
                DrinkStat(label: "Volume", value: "25 ml")
                statDivider
                DrinkStat(label: "Extraction", value: "18 sec")
            }
            // Dark, not a white wash: a translucent light fill over the warm
            // background goes muddy, and the card stops reading as a surface.
            .background(.black.opacity(0.26), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.top, 4)
        }
        .frame(width: 380, alignment: .leading)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.10))
            .frame(height: 1)
            .padding(.horizontal, 16)
    }
}

private struct DrinkStat: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
    }
}
