import SwiftUI
import XCTest
@testable import ShotKit

/// Proves the annotations actually draw on every platform the package declares,
/// not merely that they compile.
///
/// Deliberately free of AppKit: the other capture tests are macOS-only because
/// they snapshot a real `NSWindow`, which left iOS covered by the compiler
/// alone. `ImageRenderer` and `CGImage` exist on both, so these run on both.
final class AnnotationRenderingTests: XCTestCase {

    /// A ring with no note still has to put its colour on the canvas.
    @MainActor
    func testHighlightDrawsItsRing() throws {
        let view = Color.black
            .frame(width: 120, height: 60)
            .shotHighlight(
                nil,
                style: HighlightStyle(color: .yellow, lineWidth: 4, fillOpacity: 0)
            )
            .frame(width: 200, height: 140)

        XCTAssertGreaterThan(try yellowPixels(of: view), 50, "The ring must be drawn")
    }

    /// `.contained` exists so a ring on a view that reaches its container's edge
    /// stays inside it. Rendered at the view's exact size, a surrounding ring is
    /// clipped away and a contained one survives.
    @MainActor
    func testContainedRingSurvivesAtTheContainersEdge() throws {
        func ring(_ fit: HighlightRingFit) -> some View {
            Color.black
                .frame(width: 160, height: 44)
                .shotHighlight(nil, style: HighlightStyle(
                    color: .yellow, lineWidth: 4, inset: 6, fillOpacity: 0, fit: fit
                ))
                // No slack: exactly the highlighted view's bounds, as a
                // full-width row inside a window has.
                .frame(width: 160, height: 44)
                .clipped()
        }

        XCTAssertGreaterThan(try yellowPixels(of: ring(.contained)), 50,
                             "A contained ring must stay within the bounds")
    }

    /// The callout's whole purpose is drawing outside the marked control, so the
    /// note and leader must appear well away from it.
    @MainActor
    func testCalloutDrawsRingLeaderAndNote() throws {
        let view = VStack {
            Circle()
                .fill(.black)
                .frame(width: 24, height: 24)
                .shotCalloutTarget("dot")
            Spacer()
        }
        .frame(width: 320, height: 240)
        .shotCallouts([
            ShotCallout("dot", "A dot", detail: "Explained from outside.",
                        side: .bottom, shape: .circle)
        ])

        // Ring, leader and a 260pt note: far more than a bare ring would give.
        XCTAssertGreaterThan(try yellowPixels(of: view), 500,
                             "Ring, leader line and note must all be drawn")
    }

    /// A target with no matching callout must draw nothing at all.
    @MainActor
    func testUnmatchedTargetDrawsNothing() throws {
        let view = Circle()
            .fill(.black)
            .frame(width: 24, height: 24)
            .shotCalloutTarget("dot")
            .frame(width: 320, height: 240)
            .shotCallouts([ShotCallout("other", "Not this one")])

        XCTAssertEqual(try yellowPixels(of: view), 0, "An unmatched target must draw nothing")
    }

    // MARK: Pixels

    /// Counts strongly yellow pixels, which is the only colour the annotations
    /// introduce in these fixtures.
    @MainActor
    private func yellowPixels(of view: some View) throws -> Int {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage, "ImageRenderer produced nothing")

        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(
            CGContext(
                data: &pixels,
                width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var count = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Int(pixels[index])
            let green = Int(pixels[index + 1])
            let blue = Int(pixels[index + 2])
            if red > 180, green > 160, blue < 110 { count += 1 }
        }
        return count
    }
}
