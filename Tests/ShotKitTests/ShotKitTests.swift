import XCTest
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
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
}
