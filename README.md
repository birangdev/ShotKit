# ShotKit

A tiny, project-agnostic App Store screenshot engine for SwiftUI apps on macOS
and iOS.

ShotKit renders your real views into marketing screenshots at exact App Store
pixel sizes. It captures the **live view hierarchy** from a real window, so
platform-backed content that `ImageRenderer` cannot rasterize (linear
`ProgressView`s, segmented `Picker`s, `ScrollView` bodies, Swift `Charts`) comes
out looking exactly like the running app.

## Why not `ImageRenderer`?

`ImageRenderer` rasterizes SwiftUI's own drawing but silently drops
platform-backed views. A segmented picker or a linear progress bar renders as a
red "no-entry" placeholder, and a `ScrollView`'s contents and `Charts` come out
blank. ShotKit instead hosts the view in a real window and snapshots the live
hierarchy (`cacheDisplay` on macOS, `drawHierarchy` on iOS), so what you capture
is what the user sees, at the screen's backing scale (2x on Retina gives a
2880x1800 image from a 1440x900 canvas).

## Features

- **True-to-app capture** of real controls and charts, not just SwiftUI drawing.
- **Auto-fit composition.** `ShotCard` wraps your view in an optional headline +
  marketing card and scales the whole thing to fit the canvas, so a
  compact popover stays large while a tall settings/scroll window shrinks just
  enough to be captured whole. Nothing clips, with no per-screenshot tuning.
- **Optional captions.** Pass `title: nil` to `ShotCard` to capture the framed
  shot without any headline/subtitle text, just the view.
- **iPhone device frames.** Wrap iOS screens in `DeviceFrame` for a real notch,
  status bar, and bezel, so shots read as phone screenshots, not flat images.
- **Customizable background.** `ShotCard` defaults to a dark gradient, but
  takes any `View` as its `background` — a brand color, a different gradient,
  an image — set per scene.
- **Exact App Store sizes** via `ScreenshotSpec` / `AppStoreSize` (macOS and iOS
  presets).
- **Batch export** to a folder as `<name>.png`.

## Requirements

- macOS 13+ or iOS 16+
- A live UI session. Capture uses a real (briefly on-screen) window, so ShotKit
  needs a window server / active window scene — run it from your app, or from a
  small executable that brings up `NSApplication` (see the example's
  `CafeExportTool`). A plain script with no app context won't render.

## Installation

Swift Package Manager. Add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/birangdev/ShotKit.git", from: "1.0.0")
]
```

and add `"ShotKit"` to your target's `dependencies`. In Xcode:
**File > Add Package Dependencies…** and enter
`https://github.com/birangdev/ShotKit.git`.

The product is built as a static library, so if your only call sites are
compiled out (for example behind `#if DEBUG`), the linker drops ShotKit from
your Release binary.

## Usage

Describe each screenshot as a `ScreenshotScene`: give it a `spec` (name + size)
and a `makeContent()` that returns the view to capture. `ShotCard` gives you a
ready-made marketing layout, but you can return any view.

```swift
import ShotKit
import SwiftUI

struct MenuScene: ScreenshotScene {
    var spec: ScreenshotSpec { ScreenshotSpec("01-overview") }

    @MainActor
    func makeContent() -> AnyView {
        AnyView(
            ShotCard(
                "Your limits, at a glance",
                subtitle: "Live usage, right in your menu bar",
                accent: .green
            ) {
                // Your real view, at its natural size.
                MenuBarView(model: .demo)
                    .fixedSize()
                    .background(Color(nsColor: .windowBackgroundColor))
            }
        )
    }
}
```

Then export a batch to a folder:

```swift
@MainActor
func exportScreenshots(to folder: URL) {
    let scenes: [ScreenshotScene] = [MenuScene(), /* ... */]
    let urls = ShotKit.export(scenes, to: folder)
    print("Wrote \(urls.count) screenshots to \(folder.path)")
}
```

`ShotKit.export` creates the folder if needed and writes one PNG per scene named
after its `spec.name`. For a single image, use `ShotKit.capturePNG(_:)` and write
the `Data` yourself.

### Captions on or off

`ShotCard`'s title and subtitle are optional. Omit them to capture just the
framed view (still on the gradient background, still auto-fit) with no text:

```swift
// Marketing shot with a headline:
ShotCard("Your limits, at a glance", subtitle: "Right in your menu bar") { view }

// Same framed shot, no caption text:
ShotCard { view }
```

Thread a flag through your scenes to switch between the two for a whole batch.

### macOS windows

On macOS you usually capture a real app window or menu-bar popover directly — no
device frame needed. The default `ShotCard` gives the content a rounded "window"
look with a border and shadow, and its auto-fit scales it to the canvas:

```swift
ShotCard("Everything at a glance", subtitle: "Right in your menu bar") {
    MenuBarView(model: .demo)          // your real SwiftUI view
        .fixedSize()                   // natural window size
        .background(Color(nsColor: .windowBackgroundColor))
}
```

Keep `framed: true` (the default) on macOS. `DeviceFrame` is for iOS screens (see
below); you don't use it for Mac windows.

### iPhone device frames

For iOS screenshots, wrap the screen in `DeviceFrame` so it reads as a real
phone, and pass `framed: false` to `ShotCard` so it doesn't add a Mac-window
border around the device:

```swift
ShotCard("Order in seconds", subtitle: "Your usual, one tap away", framed: false) {
    DeviceFrame {
        MyScreen().frame(width: 393, height: 852)
    }
}
```

`DeviceFrame` draws the bezel, a notch (or `.dynamicIsland`), a status bar, and
side buttons from pure SwiftUI shapes. Size the screen content yourself; content
taller than the device is clipped to what fits. Options:

```swift
DeviceFrame(
    cutout: .notch,            // .dynamicIsland / .none
    showsStatusBar: true,
    statusBarTime: "9:41",
    lightStatusBar: true,      // white glyphs for dark content, false for light
    showsSideButtons: true
) { screen }
```

### Custom background

`ShotCard` defaults to a dark gradient, but takes any `View` as its
`background` — set it per scene to brand a batch differently, or to match a
scene's accent:

```swift
ShotCard("Fuel up", subtitle: "Track every cup", background: {
    LinearGradient(colors: [.brown, .black], startPoint: .top, endPoint: .bottom)
}) {
    view
}
```

Pass a plain `Color`, an `Image`, or any composed view — it fills the whole
canvas behind the caption and framed content, same as the default gradient.

### Tips for the captured view

- Return the view at its **natural size** (`.fixedSize()`), or pin only the axis
  you want fixed. `ShotCard` scales the result to fit, so a `ScrollView` or
  grouped `Form` given `.fixedSize(vertical: true)` expands to its full content
  height and gets captured whole rather than clipped to a scrolling viewport.
- Drive the view from a demo/fixture model so it renders a known state and does
  not depend on live data. Because capture runs a real run loop, the view's
  `onAppear` will fire, so make sure your model does not overwrite the fixture.

### Headless export (optional)

Because capture needs a window server, trigger it from inside your app. A common
pattern is an environment-variable hook that exports and quits, so screenshots
can be regenerated from the command line:

```swift
// In your AppDelegate / applicationDidFinishLaunching:
if ProcessInfo.processInfo.environment["EXPORT_SHOTS"] != nil {
    let folder = /* a folder your app can write to */
    ShotKit.export(allScenes, to: folder)
    NSApp.terminate(nil)
}
```

```sh
EXPORT_SHOTS=1 path/to/YourApp.app/Contents/MacOS/YourApp
```

## Example

`Examples/CafeApp` is a self-contained example that captures three screens of
[CafeApp](https://github.com/Arashk-A/CafeApp), a coffee-ordering app, in the
order the app navigates them: Home → coffee styles → size → extras. It stands in for the
app's RealmSwift models and custom artwork with fixture data (`CoffeesMock.json`)
and SF Symbols, so it builds on its own with no third-party dependencies. It's
the file to copy from to see how to drive ShotKit: each screen is a full iPhone
`DeviceFrame` inside a `ShotCard`, over a custom mocha `background`.

| Home | Styles | Size | Extras |
| --- | --- | --- | --- |
| ![Home](Examples/CafeApp/Screenshots/01-home.png) | ![Coffee styles](Examples/CafeApp/Screenshots/02-coffees.png) | ![Size](Examples/CafeApp/Screenshots/03-size.png) | ![Extras](Examples/CafeApp/Screenshots/04-extras.png) |

Regenerate the screenshots:

```sh
swift run CafeExportTool Examples/CafeApp/Screenshots
```

The example targets aren't part of the `ShotKit` library product, so they're
never pulled into an app that depends on ShotKit — they only build when you
build this repo. See `Examples/CafeApp/README.md` for details.

## API

| Type | Purpose |
| --- | --- |
| `ScreenshotSpec` | A screenshot's output name, point size, and scale. |
| `AppStoreSize` | Standard canvas sizes. macOS: `.macPoints` (1440x900 @2), `.macPointsAlt` (1280x800 @2). iOS: `.iPhone67` (@3 -> 1290x2796), `.iPhone65` (@3 -> 1242x2688), `.iPad13` (@2 -> 2048x2732). |
| `ScreenshotScene` | Protocol: a `spec` plus `@MainActor func makeContent() -> AnyView`. |
| `ShotKit.capturePNG(_:)` | Captures one scene to PNG `Data`. |
| `ShotKit.export(_:to:)` | Captures many scenes and writes PNGs into a folder. |
| `ShotCard` | Marketing card: customizable background (dark gradient by default), optional headline/subtitle, auto-fit. `framed: false` drops the Mac-window border for content with its own shape. |
| `DeviceFrame` | iPhone mockup (notch or Dynamic Island, status bar, side buttons) wrapping your screen content. Pair with `ShotCard(framed: false)`. |
| `ScaledContent` / `ScaledLayout` | Scale a view while reserving its scaled size in layout (used by `ShotCard`; reusable). |

### `ScreenshotSpec`

```swift
ScreenshotSpec("05-history")                                          // 1440x900 @2x (mac)
ScreenshotSpec("wide", pointSize: AppStoreSize.macPointsAlt)          // 1280x800 @2x (mac)
ScreenshotSpec("phone", pointSize: AppStoreSize.iPhone67, scale: 3)   // 1290x2796 (iOS)
```

`pixelSize = pointSize * scale`. Pick a `pointSize` and `scale` whose product is
a size the App Store accepts (for example 1440x900 @2x = 2880x1800).

## How it works

1. `makeContent()` is framed to `spec.pointSize` and hosted in a real window in
   dark appearance (`NSWindow` on macOS, `UIWindow` on iOS).
2. The window is briefly shown so SwiftUI, native controls, and Charts lay out
   and draw, then the hierarchy is snapshotted (`cacheDisplay` on macOS,
   `drawHierarchy` on iOS) at `spec.scale`.
3. `ShotCard` composes the marketing card and uses `ViewThatFits` over a set of
   candidate scales. Each candidate reserves its true scaled size via
   `ScaledLayout`, so the largest one that actually fits is chosen and nothing
   overflows the canvas.

## License

MIT — see [LICENSE](LICENSE).
