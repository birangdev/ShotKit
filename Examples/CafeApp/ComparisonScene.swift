import ShotKit
import SwiftUI

// MARK: - ImageRenderer vs ShotKit, side by side
//
// The same `ControlsPanel`, shown twice: on the left the bitmap SwiftUI's
// `ImageRenderer` produced, on the right the live view ShotKit captures. The
// tool (`ComparisonTool/main.swift`) renders the left image with `ImageRenderer`
// first, then hands it in here so ShotKit composes the finished picture in one
// capture.

public struct RendererComparisonScene: ScreenshotScene {
    private let rendererImage: Image

    public init(rendererImage: Image) {
        self.rendererImage = rendererImage
    }

    public var spec: ScreenshotSpec {
        ScreenshotSpec(
            "renderer-comparison",
            pointSize: CGSize(width: 1520, height: 1180),
            scale: 2
        )
    }

    @MainActor
    public func makeContent() -> AnyView {
        AnyView(
            ShotCard(
                "ImageRenderer drops native controls. ShotKit keeps them.",
                subtitle: "The same SwiftUI view. Rasterized with ImageRenderer on the left, captured from the live view hierarchy by ShotKit on the right.",
                accent: .green,
                framed: false,
                background: {
                    LinearGradient(
                        colors: [Color(red: 0.06, green: 0.09, blue: 0.13), .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            ) {
                HStack(alignment: .top, spacing: 48) {
                    panel(label: "ImageRenderer", ok: false) {
                        rendererImage
                            .resizable()
                            .frame(width: 460, height: 560)
                    }
                    panel(label: "ShotKit", ok: true) {
                        ControlsPanel()
                    }
                }
            }
        )
    }

    private func panel<Content: View>(
        label: String,
        ok: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(ok ? .green : .red)
                Text(label)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            content()
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                )
        }
    }
}
