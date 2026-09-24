import SwiftUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// A photographic background that fills the canvas without distorting.
///
/// A bare `Image` is the wrong tool here: `.resizable()` stretches to the
/// canvas's aspect ratio, and `.scaledToFit` letterboxes. This scales to
/// **fill** and centre-crops the overflow, which is what a wallpaper needs.
///
/// Supply your own image. ShotKit deliberately bundles none: every project
/// wants a different one, and shipping photographs would add weight and
/// licensing questions to a package that is otherwise pure code.
///
/// ```swift
/// ShotCard("Your limits, at a glance", background: {
///     ShotBackground(url: wallpaperURL, dim: 0.45)
/// }) {
///     MenuBarFrame(statusText: "66%") { menu }
/// }
/// ```
public struct ShotBackground: View {
    private let image: Image?

    /// Darkens the image so light caption text stays readable. 0 leaves it
    /// untouched; around 0.4–0.6 suits a busy photo under white text.
    public var dim: Double
    /// Blur radius. A little blur pushes the background back and stops detail
    /// competing with the UI in front of it.
    public var blur: CGFloat
    /// Drawn when no image loads, so a missing file degrades to a usable
    /// gradient rather than an empty frame.
    public var fallback: LinearGradient

    public init(
        image: Image?,
        dim: Double = 0.35,
        blur: CGFloat = 0,
        fallback: LinearGradient = ShotBackground.defaultFallback
    ) {
        self.image = image
        self.dim = dim
        self.blur = blur
        self.fallback = fallback
    }

    /// Loads from a file URL. Returns a fallback gradient if the file is
    /// missing or unreadable.
    public init(
        url: URL?,
        dim: Double = 0.35,
        blur: CGFloat = 0,
        fallback: LinearGradient = ShotBackground.defaultFallback
    ) {
        self.init(image: Self.loadImage(at: url), dim: dim, blur: blur, fallback: fallback)
    }

    public static let defaultFallback = LinearGradient(
        colors: [Color(red: 0.06, green: 0.09, blue: 0.13), .black],
        startPoint: .top,
        endPoint: .bottom
    )

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                fallback

                if let image {
                    image
                        .resizable()
                        // Fill, then clip: never distort the photograph.
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: blur)
                        .clipped()
                }

                if dim > 0 {
                    Color.black.opacity(dim)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .ignoresSafeArea()
    }

    private static func loadImage(at url: URL?) -> Image? {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        #if canImport(AppKit)
        guard let nsImage = NSImage(contentsOf: url) else { return nil }
        return Image(nsImage: nsImage)
        #elseif canImport(UIKit)
        guard let data = try? Data(contentsOf: url),
              let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #else
        return nil
        #endif
    }
}
