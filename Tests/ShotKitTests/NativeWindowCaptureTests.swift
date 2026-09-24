#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import ShotKit

final class NativeWindowCaptureTests: XCTestCase {
    @MainActor
    func testPixelDimensionsRespectRequestedScale() throws {
        let pixels = try NativeWindowCapture.pixelSize(for: CGSize(width: 801, height: 603), scale: 1.5)
        XCTAssertEqual(pixels.width, 1202)
        XCTAssertEqual(pixels.height, 905)
    }

    @MainActor
    func testInvalidGeometryIsRejectedBeforeCreatingAWindow() {
        for size in [CGSize.zero, CGSize(width: -1, height: 200),
                     CGSize(width: CGFloat.infinity, height: 200),
                     CGSize(width: CGFloat.nan, height: 200)] {
            XCTAssertThrowsError(try NativeWindowCapture.makeWindow(
                configuration: NativeWindowConfiguration(title: "Invalid", contentSize: size),
                configure: { _ in XCTFail("Invalid dimensions must not reach window configuration") },
                content: Color.red
            ))
        }
        for scale in [CGFloat(0), -1, .infinity, .nan, .greatestFiniteMagnitude, 0.0001] {
            XCTAssertThrowsError(try NativeWindowCapture.pixelSize(
                for: CGSize(width: 800, height: 600), scale: scale
            ))
        }
    }

    @MainActor
    func testNativeFrameAndContentViewportAreSeparate() throws {
        try requireDisplay()
        let size = CGSize(width: 820, height: 560)
        let window = try NativeWindowCapture.makeWindow(
            configuration: NativeWindowConfiguration(title: "Settings", contentSize: size),
            configure: { $0.toolbarStyle = .unified },
            content: TestSplitView()
        )
        defer { window.close() }
        XCTAssertTrue(window.styleMask.contains(.titled))
        XCTAssertTrue(window.canBecomeKey)
        XCTAssertEqual(window.title, "Settings")
        XCTAssertNotNil(window.standardWindowButton(.closeButton))
        XCTAssertEqual(window.contentView?.bounds.size, size)
        XCTAssertGreaterThan(window.frame.height, size.height)
        XCTAssertEqual(window.frame.width, size.width)
    }

    @MainActor
    func testSplitViewKeepsViewportAndWaitsForPreparation() async throws {
        try requireDisplay()
        var capturedWindow: NSWindow?
        var ready = false
        for size in [CGSize(width: 800, height: 520), CGSize(width: 1100, height: 700)] {
            ready = false
            let result = try await NativeWindowCapture.withWindow(
                configuration: NativeWindowConfiguration(title: "Settings", contentSize: size),
                prepare: { window in
                    capturedWindow = window
                    XCTAssertTrue(window.isVisible)
                    await Task.yield()
                    ready = true
                },
                content: { TestSplitView() }
            ) { window in
                XCTAssertTrue(ready, "Capture must follow async application readiness")
                XCTAssertEqual(window.contentView?.bounds.size, size)
                return 42
            }
            XCTAssertEqual(result, 42)
            XCTAssertFalse(try XCTUnwrap(capturedWindow).isVisible)
        }
    }

    /// Restoration is asserted through window *ordering*, not key status.
    ///
    /// `swift test` runs an unbundled binary: its activation policy is
    /// `.prohibited`, `setActivationPolicy(.regular)` succeeds but the process
    /// still never becomes active, and a window in an inactive app can never be
    /// key. Asserting `isKeyWindow` therefore tested the harness, not the
    /// library. What the library actually promises — that the previous window is
    /// ordered back to the front — is observable either way, so the fixture puts
    /// a second window behind it to make that promise measurable.
    @MainActor
    func testPreparationFailureClosesWindowAndRestoresPreviousKeyWindow() async throws {
        try requireDisplay()
        let behind = try NativeWindowCapture.makeWindow(
            configuration: NativeWindowConfiguration(title: "Behind", contentSize: CGSize(width: 400, height: 300)),
            configure: { _ in }, content: Color.blue
        )
        behind.makeKeyAndOrderFront(nil)
        defer { behind.close() }

        let previous = try NativeWindowCapture.makeWindow(
            configuration: NativeWindowConfiguration(title: "Previous", contentSize: CGSize(width: 400, height: 300)),
            configure: { _ in }, content: Color.green
        )
        previous.makeKeyAndOrderFront(nil)
        defer { previous.close() }
        XCTAssertLessThan(previous.orderedIndex, behind.orderedIndex, "Fixture: previous starts in front")

        var temporary: NSWindow?
        do {
            let _: Void = try await NativeWindowCapture.withWindow(
                configuration: configuration,
                prepare: { window in
                    temporary = window
                    throw FixtureError.notReady
                },
                content: { TestSplitView() },
                operation: { _ in XCTFail("Must not capture when preparation fails") }
            )
            XCTFail("Expected preparation error")
        } catch FixtureError.notReady {
            XCTAssertFalse(try XCTUnwrap(temporary).isVisible)
            XCTAssertLessThan(
                previous.orderedIndex, behind.orderedIndex,
                "The window that was front before the capture must be front again after it"
            )
            // Free where the process can actually activate — a host app, or a
            // developer running the suite from Xcode.
            if NSApp.isActive {
                XCTAssertTrue(previous.isKeyWindow)
            }
        }
    }

    @MainActor
    func testCaptureFailureClosesTemporaryWindow() async throws {
        try requireDisplay()
        var temporary: NSWindow?
        do {
            let _: Void = try await NativeWindowCapture.withWindow(
                configuration: configuration,
                content: { TestSplitView() }
            ) { window in
                temporary = window
                throw FixtureError.captureFailed
            }
            XCTFail("Expected capture error")
        } catch FixtureError.captureFailed {
            XCTAssertFalse(try XCTUnwrap(temporary).isVisible)
        }
    }

    @MainActor
    func testCancellationClosesTemporaryWindow() async throws {
        try requireDisplay()
        var temporary: NSWindow?
        let task = Task { @MainActor in
            try await NativeWindowCapture.withWindow(
                configuration: configuration,
                prepare: { window in
                    temporary = window
                    withUnsafeCurrentTask { $0?.cancel() }
                    try Task.checkCancellation()
                },
                content: { TestSplitView() },
                operation: { _ in XCTFail("A cancelled capture must not run") }
            )
        }
        do {
            try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertFalse(try XCTUnwrap(temporary).isVisible)
        }
    }

    @MainActor
    func testExistingHiddenWindowIsRejectedWithoutShowingIt() async throws {
        guard #available(macOS 14.0, *) else { throw XCTSkip("Requires macOS 14") }
        try requireDisplay()
        let window = try NativeWindowCapture.makeWindow(
            configuration: configuration, configure: { _ in }, content: TestSplitView()
        )
        defer { window.close() }
        do {
            _ = try await ShotKit.captureWindow(window)
            XCTFail("Expected a hidden-window error")
        } catch NativeWindowCaptureError.windowNotVisible {
            XCTAssertFalse(window.isVisible)
        }
    }

    /// Runs unconditionally. It used to be opt-in behind an environment
    /// variable because ScreenCaptureKit demands a Screen Recording grant even
    /// for the caller's own windows — but the WindowServer path needs no grant
    /// at all for them, so the contract can be checked on any machine.
    ///
    /// Both paths are held to the same contract, which is the point: whichever
    /// one `.automatic` resolves to at runtime, callers get the same bitmap.
    @MainActor
    func testCompositedSplitViewContainsBothColumnsAtRequestedScale() async throws {
        // The capture API itself needs macOS 14, so on 13 there is nothing to
        // assert. This is unrelated to the old permission gate: both paths run
        // without a Screen Recording grant wherever the API exists.
        guard #available(macOS 14.0, *) else {
            throw XCTSkip("ShotKit.captureWindow requires macOS 14")
        }
        try requireDisplay()
        try await assertCaptureContainsBothColumns(method: .windowServer)

        // Only when the grant is already present. Absent it, the path that
        // actually runs on an unprivileged machine has still been covered.
        if CGPreflightScreenCaptureAccess() {
            try await assertCaptureContainsBothColumns(method: .screenCaptureKit)
        }
    }

    @available(macOS 14.0, *)
    @MainActor
    private func assertCaptureContainsBothColumns(
        method: NativeWindowCaptureMethod,
        line: UInt = #line
    ) async throws {
        var configuration = self.configuration
        configuration.method = method
        let snapshot = try await ShotKit.captureWindow(configuration: configuration) {
            TestSplitView()
        }
        XCTAssertEqual(snapshot.pointSize.width, configuration.contentSize.width, line: line)
        XCTAssertGreaterThan(snapshot.pointSize.height, configuration.contentSize.height, line: line)
        XCTAssertEqual(
            snapshot.cgImage.width,
            Int((snapshot.pointSize.width * configuration.scale).rounded()),
            line: line
        )
        XCTAssertEqual(
            snapshot.cgImage.height,
            Int((snapshot.pointSize.height * configuration.scale).rounded()),
            line: line
        )

        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: snapshot.pngData()), line: line)
        var redPixels = 0
        var bluePixels = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 8) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 8) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.redComponent > 0.7 && color.blueComponent < 0.3 { redPixels += 1 }
                if color.blueComponent > 0.7 && color.redComponent < 0.3 { bluePixels += 1 }
            }
        }
        XCTAssertGreaterThan(redPixels, 100, "The sidebar must actually appear in the capture", line: line)
        XCTAssertGreaterThan(bluePixels, 100, "The detail column must actually appear in the capture", line: line)

        // The marketing layout scales the bitmap and reserves the scaled size.
        let renderer = ImageRenderer(content: ScaledContent(scale: 0.5) { snapshot })
        let composed = try XCTUnwrap(renderer.cgImage, line: line)
        XCTAssertEqual(composed.width, Int((snapshot.pointSize.width * 0.5).rounded(.up)), line: line)
        XCTAssertEqual(composed.height, Int((snapshot.pointSize.height * 0.5).rounded(.up)), line: line)
    }

    @MainActor
    private func requireDisplay() throws {
        _ = NSApplication.shared
        try XCTSkipIf(NSScreen.main == nil, "Requires a live window server")
    }

    private var configuration: NativeWindowConfiguration {
        NativeWindowConfiguration(title: "Split View Test", contentSize: CGSize(width: 800, height: 520), scale: 1.5)
    }

    private enum FixtureError: Error { case notReady, captureFailed }
}

private struct TestSplitView: View {
    var body: some View {
        NavigationSplitView {
            Color(red: 1, green: 0, blue: 0)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            Color(red: 0, green: 0, blue: 1)
        }
        .navigationSplitViewStyle(.balanced)
    }
}
#endif
