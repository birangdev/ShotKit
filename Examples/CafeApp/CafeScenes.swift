import ShotKit
import SwiftUI

// MARK: - CafeApp example — ScreenshotScenes
//
// Captures the three CafeApp screens in the app's real navigation order —
// Home -> coffee styles -> size — each as a full iPhone screen inside a
// `DeviceFrame`, with a marketing caption above it (like an App Store hero).
// Uses CafeApp's real fixture data (CafeMockData.swift) and a custom mocha
// `background` so the black bezel stands out. This is the file to copy from to
// see how to drive ShotKit: a `ScreenshotScene` returns `ShotCard { DeviceFrame
// { yourScreen } }`.

struct HomeScene: ScreenshotScene {
    var spec: ScreenshotSpec {
        ScreenshotSpec("01-home", pointSize: AppStoreSize.iPhone67, scale: 3)
    }

    @MainActor
    func makeContent() -> AnyView {
        AnyView(
            ShotCard("Brew with a tap", subtitle: "Start your cup instantly",
                     accent: .orange, framed: false, background: { cafeMarketingBackground }) {
                DeviceFrame { CafeScreen { HomeScreen() } }
            }
        )
    }
}

struct StyleScene: ScreenshotScene {
    var spec: ScreenshotSpec {
        ScreenshotSpec("02-coffees", pointSize: AppStoreSize.iPhone67, scale: 3)
    }

    @MainActor
    func makeContent() -> AnyView {
        AnyView(
            ShotCard("Your roast", subtitle: "Three ways to brew",
                     accent: .orange, framed: false, background: { cafeMarketingBackground }) {
                DeviceFrame { CafeScreen { StyleScreen() } }
            }
        )
    }
}

struct SizeScene: ScreenshotScene {
    var spec: ScreenshotSpec {
        ScreenshotSpec("03-size", pointSize: AppStoreSize.iPhone67, scale: 3)
    }

    @MainActor
    func makeContent() -> AnyView {
        AnyView(
            ShotCard("Your pour", subtitle: "From shot to Venti",
                     accent: .orange, framed: false, background: { cafeMarketingBackground }) {
                DeviceFrame { CafeScreen { SizeScreen() } }
            }
        )
    }
}

struct ExtrasScene: ScreenshotScene {
    var spec: ScreenshotSpec {
        ScreenshotSpec("04-extras", pointSize: AppStoreSize.iPhone67, scale: 3)
    }

    @MainActor
    func makeContent() -> AnyView {
        AnyView(
            ShotCard("Make it yours", subtitle: "Sugar and milk, your way",
                     accent: .orange, framed: false, background: { cafeMarketingBackground }) {
                DeviceFrame { CafeScreen { ExtrasScreen() } }
            }
        )
    }
}

public enum CafeExampleScenes {
    /// All scenes, in navigation order, ready to pass to `ShotKit.export`.
    public static let all: [ScreenshotScene] = [HomeScene(), StyleScene(), SizeScene(), ExtrasScene()]
}
