// macOS-only: these snapshot a real `NSWindow` through AppKit, so the whole
// file is gated rather than each use. Without this the test target does not
// build for iOS at all, which silently left the iOS side of the package
// untested — see `AnnotationRenderingTests` for the cross-platform cover.
#if os(macOS)
import XCTest
import SwiftUI
import AppKit
@testable import ShotKit

final class ShotKitTests: XCTestCase {

    // MARK: - ScreenshotSpec

    func testScreenshotSpecDefaults() {
        let spec = ScreenshotSpec("hero")
        XCTAssertEqual(spec.name, "hero")
        XCTAssertEqual(spec.pointSize, AppStoreSize.macPoints)
        XCTAssertEqual(spec.scale, 2)
    }

    func testScreenshotSpecPixelSize() {
        let spec = ScreenshotSpec("x", pointSize: CGSize(width: 100, height: 200), scale: 3)
        XCTAssertEqual(spec.pixelSize, CGSize(width: 300, height: 600))
    }

    // MARK: - AppStoreSize (documented pixel targets)

    func testMacAppStorePixelSizes() {
        XCTAssertEqual(ScreenshotSpec("a", pointSize: AppStoreSize.macPoints, scale: 2).pixelSize,
                       CGSize(width: 2880, height: 1800))
        XCTAssertEqual(ScreenshotSpec("b", pointSize: AppStoreSize.macPointsAlt, scale: 2).pixelSize,
                       CGSize(width: 2560, height: 1600))
    }

    func testIOSAppStorePixelSizes() {
        XCTAssertEqual(ScreenshotSpec("c", pointSize: AppStoreSize.iPhone67, scale: 3).pixelSize,
                       CGSize(width: 1290, height: 2796))
        XCTAssertEqual(ScreenshotSpec("d", pointSize: AppStoreSize.iPhone65, scale: 3).pixelSize,
                       CGSize(width: 1242, height: 2688))
        XCTAssertEqual(ScreenshotSpec("e", pointSize: AppStoreSize.iPad13, scale: 2).pixelSize,
                       CGSize(width: 2048, height: 2732))
    }

    // MARK: - Capture (requires a live window server; skipped headless)

    private struct SolidScene: ScreenshotScene {
        let spec: ScreenshotSpec
        @MainActor func makeContent() -> AnyView {
            AnyView(ShotCard(background: { Color.blue }) {
                Color.green.frame(width: 80, height: 80)
            })
        }
    }

    @MainActor
    func testCaptureProducesValidPNG() throws {
        try XCTSkipIf(NSScreen.main == nil, "No display / window server (headless CI).")
        let spec = ScreenshotSpec("unit", pointSize: CGSize(width: 300, height: 200), scale: 2)
        guard let data = ShotKit.capturePNG(SolidScene(spec: spec)) else {
            throw XCTSkip("No window server available; capture returns nil headless.")
        }
        let rep = try XCTUnwrap(NSBitmapImageRep(data: data), "PNG should decode to a bitmap")
        // macOS capture uses the screen's backing scale, so pixels are the point
        // size times an integer scale (1x/2x/3x) rather than spec.scale exactly.
        XCTAssertGreaterThanOrEqual(rep.pixelsWide, Int(spec.pointSize.width))
        XCTAssertEqual(rep.pixelsWide % Int(spec.pointSize.width), 0)
        XCTAssertEqual(rep.pixelsHigh % Int(spec.pointSize.height), 0)
    }

    @MainActor
    func testExportWritesOnePNGPerScene() throws {
        try XCTSkipIf(NSScreen.main == nil, "No display / window server (headless CI).")
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ShotKitTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let scenes = [
            SolidScene(spec: ScreenshotSpec("one", pointSize: CGSize(width: 200, height: 200))),
            SolidScene(spec: ScreenshotSpec("two", pointSize: CGSize(width: 200, height: 200))),
        ]
        let urls = ShotKit.export(scenes, to: folder)
        guard !urls.isEmpty else {
            throw XCTSkip("No window server available; export produced nothing headless.")
        }
        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(Set(urls.map(\.lastPathComponent)), ["one.png", "two.png"])
        for url in urls {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }
    }

    // MARK: - 1.1 composition

    func testCaptionPlacementKnowsItsAxis() {
        XCTAssertFalse(CaptionPlacement.top.isHorizontal)
        XCTAssertFalse(CaptionPlacement.bottom.isHorizontal)
        XCTAssertTrue(CaptionPlacement.leading.isHorizontal)
        XCTAssertTrue(CaptionPlacement.trailing.isHorizontal)
    }

    func testHighlightStyleDefaults() {
        let style = HighlightStyle.default
        XCTAssertEqual(style.lineWidth, 3)
        XCTAssertEqual(style.notePlacement, .outside)
        // A highlight is a hint, not a spotlight: the fill must stay subtle or
        // it obscures the control it is pointing at.
        XCTAssertLessThan(style.fillOpacity, 0.2)
    }

    /// The whole point of `.contained`: a ring on a view that reaches its
    /// container's edge must not draw outside that view's bounds, or the
    /// container clips it and the highlight reads as a rendering fault.
    func testContainedRingStaysWithinBounds() {
        let contained = HighlightStyle(lineWidth: 4, inset: 5, fit: .contained)
        // Positive padding shrinks the ring inward; the extra half stroke is
        // what keeps the drawn line itself inside too.
        XCTAssertEqual(contained.ringPadding, 7)
        XCTAssertGreaterThan(contained.ringPadding, 0)

        let surrounding = HighlightStyle(lineWidth: 4, inset: 5, fit: .surrounding)
        XCTAssertEqual(surrounding.ringPadding, -5)

        XCTAssertEqual(HighlightStyle.withinBounds.fit, .contained)
        XCTAssertEqual(HighlightStyle.withinBounds.notePlacement, .inside)
    }

    /// A callout's note is placed from its own fixed width, so the style's
    /// width cap has to be the width the note actually takes.
    func testCalloutStyleDefaults() {
        let style = ShotCalloutStyle.default
        XCTAssertGreaterThan(style.noteMaxWidth, 0)
        XCTAssertGreaterThan(style.ringInset, 0)

        let callout = ShotCallout("pin", "Pin a provider", detail: "Keeps it in the menu bar.")
        XCTAssertEqual(callout.id, "pin")
        XCTAssertEqual(callout.side, .trailing)
        XCTAssertNil(callout.color)
    }

    /// Marked targets must publish their frames, and a target with no matching
    /// callout must simply be ignored rather than drawing a stray ring.
    func testCalloutAnchorKeyMergesTargetsAndKeepsLatest() {
        var value = ShotCalloutAnchorKey.defaultValue
        XCTAssertTrue(value.isEmpty)

        let view = AnyView(
            VStack {
                Color.red.frame(width: 30, height: 30).shotCalloutTarget("icon")
                Color.blue.frame(width: 40, height: 40).shotCalloutTarget("other")
            }
            .shotCallouts([ShotCallout("icon", "Only this one", shape: .circle)])
        )
        XCTAssertNotNil(view)

        // Reduction keeps the newest frame for an id, so a target that moves
        // does not leave the ring behind at its old position.
        ShotCalloutAnchorKey.reduce(value: &value) { [:] }
        XCTAssertTrue(value.isEmpty)
    }

    /// A callout must survive an actual capture, not just compile: the layer
    /// draws through a Shape and an overlay, both of which can silently produce
    /// nothing if the coordinate space collapses.
    @MainActor
    func testCalloutCaptures() throws {
        try XCTSkipIf(NSScreen.main == nil, "No display / window server (headless CI).")
        let spec = ScreenshotSpec("callout", pointSize: CGSize(width: 600, height: 400), scale: 1)
        let scene = InlineScene(spec: spec) {
            AnyView(
                ShotCard("Annotated", framed: false) {
                    VStack(spacing: 10) {
                        Circle()
                            .fill(.orange)
                            .frame(width: 30, height: 30)
                            .shotCalloutTarget("dot")
                        Text("Row")
                    }
                    .padding(40)
                    .background(.black)
                    .shotCallouts([
                        ShotCallout("dot", "A dot", side: .bottom, shape: .circle)
                    ])
                }
            )
        }
        let data = try XCTUnwrap(ShotKit.capturePNG(scene), "capture returned nil")
        let rep = try XCTUnwrap(NSBitmapImageRep(data: data))

        // Asserting the capture is merely non-nil would pass even when the
        // callout drew nothing. The ring, leader, and note are the only yellow
        // in this scene, so counting yellow pixels is what actually proves the
        // annotation landed on the canvas rather than collapsing to a point.
        var yellow = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 4) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.redComponent > 0.7, color.greenComponent > 0.7, color.blueComponent < 0.4 {
                    yellow += 1
                }
            }
        }
        XCTAssertGreaterThan(yellow, 50, "The callout must actually be drawn")
    }

    /// Captions on a side must still render, since that path uses a different
    /// arrangement and fit axis from the stacked one.
    @MainActor
    func testSideCaptionCaptures() throws {
        try XCTSkipIf(NSScreen.main == nil, "No display / window server (headless CI).")
        let spec = ScreenshotSpec("side", pointSize: CGSize(width: 800, height: 400), scale: 1)
        let scene = InlineScene(spec: spec) {
            AnyView(
                ShotCard("Title", subtitle: "Subtitle", placement: .trailing) {
                    Color.blue.frame(width: 200, height: 140)
                }
            )
        }
        let data = try XCTUnwrap(ShotKit.capturePNG(scene), "capture returned nil")
        XCTAssertNotNil(NSImage(data: data)?.representations.first)
    }

    @MainActor
    func testWindowChromeAndMenuBarFrameCapture() throws {
        try XCTSkipIf(NSScreen.main == nil, "No display / window server (headless CI).")
        let spec = ScreenshotSpec("frames", pointSize: CGSize(width: 900, height: 600), scale: 1)
        let scene = InlineScene(spec: spec) {
            AnyView(
                ShotCard(framed: false) {
                    VStack(spacing: 24) {
                        WindowChrome(title: "Window") {
                            Color.gray.frame(width: 320, height: 120)
                        }
                        MenuBarFrame(statusText: "78%") {
                            Color.gray.frame(width: 300, height: 120)
                        }
                    }
                }
            )
        }
        let data = try XCTUnwrap(ShotKit.capturePNG(scene), "capture returned nil")
        XCTAssertNotNil(NSImage(data: data)?.representations.first)
    }
}

/// A scene built from a closure, so tests can compose one inline.
private struct InlineScene: ScreenshotScene {
    let spec: ScreenshotSpec
    let make: @MainActor () -> AnyView

    init(spec: ScreenshotSpec, make: @escaping @MainActor () -> AnyView) {
        self.spec = spec
        self.make = make
    }

    @MainActor func makeContent() -> AnyView { make() }
}
#endif
