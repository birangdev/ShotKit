import SwiftUI

/// Presents a menu-bar app's popover the way people actually meet it: hanging
/// from a macOS menu bar, with the app's own status item highlighted among
/// neighbours.
///
/// Captured on its own, a menu-bar popover is just a floating rounded
/// rectangle, and nothing in the image says "this lives in your menu bar". This
/// supplies the missing context without needing a real desktop screenshot.
///
/// ```swift
/// MenuBarFrame(statusText: "78%") {
///     MenuBarView(model: .demo)
/// }
/// ```
public struct MenuBarFrame<StatusItem: View, Content: View>: View {
    /// The app's own status item, rendered highlighted as if the menu is open.
    @ViewBuilder public var statusItem: () -> StatusItem
    /// The popover itself.
    @ViewBuilder public var content: () -> Content

    /// How many system glyphs to draw. They sit to the *right* of the app's
    /// item, which is where macOS puts them: third-party items live left of the
    /// system ones.
    public var systemItems: Int
    /// Clock text at the bar's right end. Nil hides it.
    public var clock: String?
    public var barHeight: CGFloat
    /// Tint behind the bar. Translucent, so a background shows through.
    public var barTint: Color
    /// Corner radius of the bar itself. Zero by default, because a real menu
    /// bar spans the display with straight edges; inside `DesktopFrame` the
    /// screen's own clip rounds the top corners for you. Raise it only when
    /// showing the bar standalone.
    public var barCornerRadius: CGFloat
    /// Corner radius of the popover.
    public var cornerRadius: CGFloat

    @State private var anchor = MenuBarAnchor()

    public init(
        systemItems: Int = 3,
        clock: String? = "Tue 9:41",
        barHeight: CGFloat = 38,
        barTint: Color = Color.black.opacity(0.55),
        barCornerRadius: CGFloat = 0,
        cornerRadius: CGFloat = 14,
        @ViewBuilder statusItem: @escaping () -> StatusItem,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.systemItems = systemItems
        self.clock = clock
        self.barHeight = barHeight
        self.barTint = barTint
        self.barCornerRadius = barCornerRadius
        self.cornerRadius = cornerRadius
        self.statusItem = statusItem
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            menuBar
            content()
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 34, y: 16)
                // Pushed left by whatever sits to the right of the status item,
                // so the popover hangs from the item rather than the bar corner.
                .padding(.trailing, anchor.trailingInset)
        }
        .onPreferenceChange(MenuBarAnchorKey.self) { anchor = $0 }
    }

    private var menuBar: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 0)

            statusItem()
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(.white.opacity(0.18), in: Capsule())
                .background(
                    GeometryReader { item in
                        Color.clear.preference(
                            key: MenuBarAnchorKey.self,
                            value: MenuBarAnchor(
                                statusItemMaxX: item.frame(in: .named(menuBarSpace)).maxX
                            )
                        )
                    }
                )

            ForEach(0..<max(0, systemItems), id: \.self) { index in
                NeighbourGlyph(index: index)
            }

            if let clock {
                Text(clock)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.9))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: barHeight)
        .frame(maxWidth: .infinity)
        .background(barTint)
        .clipShape(RoundedRectangle(cornerRadius: barCornerRadius, style: .continuous))
        .coordinateSpace(name: menuBarSpace)
        .overlay(
            GeometryReader { bar in
                Color.clear.preference(
                    key: MenuBarAnchorKey.self,
                    value: MenuBarAnchor(barWidth: bar.size.width)
                )
            }
        )
    }
}

/// Where the status item sits relative to the bar.
///
/// A custom `HorizontalAlignment` was the obvious approach and does not work: a
/// horizontal guide set on a child of an `HStack` is not adopted by the stack
/// itself, so the bar's own trailing edge always won. Measuring both edges and
/// deriving the inset is reliable.
private struct MenuBarAnchor: Equatable {
    var barWidth: CGFloat = 0
    var statusItemMaxX: CGFloat = 0

    var trailingInset: CGFloat {
        guard barWidth > 0, statusItemMaxX > 0 else { return 0 }
        return max(0, barWidth - statusItemMaxX)
    }
}

/// Merges the two measurements, which arrive from separate readers.
private struct MenuBarAnchorKey: PreferenceKey {
    static let defaultValue = MenuBarAnchor()

    static func reduce(value: inout MenuBarAnchor, nextValue: () -> MenuBarAnchor) {
        let next = nextValue()
        if next.barWidth > 0 { value.barWidth = next.barWidth }
        if next.statusItemMaxX > 0 { value.statusItemMaxX = next.statusItemMaxX }
    }
}

private let menuBarSpace = "ShotKitMenuBar"

/// Anonymous neighbouring status items. Deliberately abstract system symbols
/// rather than recognizable third-party icons, so a marketing shot never
/// implies an association with other software.
private struct NeighbourGlyph: View {
    let index: Int

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(.white.opacity(0.55))
    }

    private var symbol: String {
        let symbols = ["battery.75", "speaker.wave.2", "wifi", "magnifyingglass", "bolt"]
        return symbols[index % symbols.count]
    }
}

public extension MenuBarFrame where StatusItem == Text {
    /// Convenience for the usual case: a short text status item such as "78%".
    init(
        statusText: String,
        systemItems: Int = 3,
        clock: String? = "Tue 9:41",
        barHeight: CGFloat = 38,
        barTint: Color = Color.black.opacity(0.55),
        barCornerRadius: CGFloat = 0,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            systemItems: systemItems,
            clock: clock,
            barHeight: barHeight,
            barTint: barTint,
            barCornerRadius: barCornerRadius,
            statusItem: { Text(statusText) },
            content: content
        )
    }
}
