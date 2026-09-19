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
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(CafeMock.coffee.types.enumerated()), id: \.element.id) { index, type in
                HStack(spacing: 14) {
                    Circle().fill(CafePalette.icon).frame(width: 30, height: 30)
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
                .modifier(HighlightIf(active: index == 1, note: "Most ordered"))

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

/// Applies `shotHighlight` to one row only, since the modifier is unconditional.
private struct HighlightIf: ViewModifier {
    let active: Bool
    let note: String

    func body(content: Content) -> some View {
        if active {
            // Inside placement: WindowChrome clips, so an outside note would
            // be cut off at the window edge.
            content.shotHighlight(
                note,
                edge: .trailing,
                style: HighlightStyle(color: CafePalette.icon, cornerRadius: 8,
                                      notePlacement: .inside)
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
                    CafeOrdersWindow()
                }
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
                MenuBarFrame(statusText: "12 ☕") {
                    CafeOrdersWindow()
                }
            }
        )
    }
}
