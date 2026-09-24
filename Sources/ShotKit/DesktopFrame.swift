import SwiftUI

/// A Mac screen: wallpaper, a menu bar welded to its top edge, and your content
/// on top.
///
/// `MenuBarFrame` alone leaves the bar floating mid-canvas, which reads wrong
/// because a real menu bar is fixed to the top of a display. Putting it inside a
/// screen gives it something to be attached to, so the popover stops looking
/// like it is hanging in space.
///
/// ```swift
/// ShotCard("Your limits, at a glance", framed: false) {
///     DesktopFrame(wallpaper: { ShotBackground(url: wallpaperURL, dim: 0.2) }) {
///         MenuBarFrame(statusText: "66%") { menu }
///     }
/// }
/// ```
///
/// Pass the whole `MenuBarFrame` as the content: it supplies its own bar, and
/// `DesktopFrame` anchors that assembly to the screen's top edge.
public struct DesktopFrame<Wallpaper: View, Content: View>: View {
    @ViewBuilder public var wallpaper: () -> Wallpaper
    @ViewBuilder public var content: () -> Content

    /// Screen size in points. Defaults to a 16:10 proportion, matching the
    /// App Store's macOS canvas.
    public var screenSize: CGSize
    public var cornerRadius: CGFloat
    /// Bezel thickness. Zero draws a bare screen with no surround.
    public var bezelWidth: CGFloat
    public var bezelColor: Color

    public init(
        screenSize: CGSize = CGSize(width: 1280, height: 800),
        cornerRadius: CGFloat = 18,
        bezelWidth: CGFloat = 12,
        bezelColor: Color = Color(white: 0.10),
        @ViewBuilder wallpaper: @escaping () -> Wallpaper,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.screenSize = screenSize
        self.cornerRadius = cornerRadius
        self.bezelWidth = bezelWidth
        self.bezelColor = bezelColor
        self.wallpaper = wallpaper
        self.content = content
    }

    public var body: some View {
        ZStack(alignment: .top) {
            wallpaper()
            // Top alignment is the whole point: the menu bar belongs against
            // the screen's top edge, not floating in the middle of it.
            content()
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .padding(bezelWidth)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius + bezelWidth, style: .continuous)
                .fill(bezelWidth > 0 ? bezelColor : .clear)
        )
        // Only outline an actual bezel. A hairline around a bare screen reads
        // as a tablet edge, which is exactly the wrong association for a Mac.
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius + bezelWidth, style: .continuous)
                .strokeBorder(.white.opacity(bezelWidth > 0 ? 0.10 : 0), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.55), radius: 50, y: 26)
    }
}

public extension DesktopFrame where Wallpaper == ShotBackground {
    /// Convenience for the usual case: a wallpaper loaded from a file.
    init(
        wallpaperURL: URL?,
        dim: Double = 0.2,
        screenSize: CGSize = CGSize(width: 1280, height: 800),
        cornerRadius: CGFloat = 18,
        bezelWidth: CGFloat = 12,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            screenSize: screenSize,
            cornerRadius: cornerRadius,
            bezelWidth: bezelWidth,
            wallpaper: { ShotBackground(url: wallpaperURL, dim: dim) },
            content: content
        )
    }
}
