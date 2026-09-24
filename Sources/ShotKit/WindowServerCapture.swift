#if os(macOS)
import AppKit

// Deliberately does not import ScreenCaptureKit. That module marks
// `CGWindowListCreateImage` unavailable rather than merely deprecated, so the
// call has to live in a file that never sees it. Keeping the WindowServer path
// here is what lets `NativeWindowCaptureMethod.automatic` fall back at all.

@MainActor
extension NativeWindowCapture {

    /// Asks the WindowServer directly for the composited window.
    ///
    /// Needs no Screen Recording grant, because a process capturing its own
    /// windows is not a privacy boundary. `.boundsIgnoreFraming` drops the
    /// shadow from the bounds, so the image is the frame rect exactly — title
    /// bar included — which is what the ScreenCaptureKit path also returns.
    static func captureThroughWindowServer(
        _ window: NSWindow,
        scale: CGFloat
    ) async throws -> WindowSnapshot {
        let id = CGWindowID(window.windowNumber)
        guard id != 0 else { throw NativeWindowCaptureError.windowNotFound }

        // A window ordered on screen moments ago may not be registered with the
        // WindowServer yet, and the call simply returns nil until it is. That
        // shows up as the first capture after app launch failing while every
        // later one succeeds, so retry briefly rather than dropping the shot.
        var image: CGImage?
        for attempt in 0..<10 {
            if attempt > 0 { try await Task.sleep(nanoseconds: 50_000_000) }
            try Task.checkCancellation()
            image = CGWindowListCreateImage(
                .null, .optionIncludingWindow, id, [.boundsIgnoreFraming, .bestResolution]
            )
            if image != nil { break }
        }
        guard let image else { throw NativeWindowCaptureError.windowNotFound }

        let pointSize = window.frame.size
        let pixels = try pixelSize(for: pointSize, scale: scale)
        // The WindowServer renders at the display's backing scale, which is the
        // screen's business and not the caller's. Resampling keeps `scale`
        // meaning the same thing on Retina, an external 1x monitor, and CI.
        return WindowSnapshot(cgImage: try resample(image, to: pixels), pointSize: pointSize)
    }

    private static func resample(
        _ image: CGImage,
        to pixels: (width: Int, height: Int)
    ) throws -> CGImage {
        guard image.width != pixels.width || image.height != pixels.height else { return image }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: pixels.width, height: pixels.height,
                bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw NativeWindowCaptureError.pngEncodingFailed
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height))
        guard let resampled = context.makeImage() else {
            throw NativeWindowCaptureError.pngEncodingFailed
        }
        return resampled
    }
}
#endif
