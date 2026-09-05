import SwiftUI

// MARK: - CafeApp example — standalone screens
//
// Simplified stand-ins for three real screens in CafeApp
// (https://github.com/Arashk-A/CafeApp), in the order the app navigates them:
// the Home "tap to start" screen, the coffee-style picker (CoffeesView), and
// the size picker (CoffeeSizeView). The originals use RealmSwift models and
// custom artwork; here they're driven by `CafeMock` (see `CafeMockData.swift`)
// and SF Symbols, so this file has no third-party dependencies. See
// `CafeScenes.swift` for the `ScreenshotScene`s that capture them with ShotKit.

// MARK: - Palette + composition

enum CafePalette {
    /// The in-app screen background (a warm, dark roast).
    static let screen = LinearGradient(
        colors: [Color(red: 0.16, green: 0.09, blue: 0.05), Color(red: 0.07, green: 0.04, blue: 0.03)],
        startPoint: .top, endPoint: .bottom
    )
    static let icon = Color(red: 0.85, green: 0.68, blue: 0.42)
    /// Row/card fill — light enough to read against the roast background.
    static let card = Color.white.opacity(0.16)
}

/// A warm mocha backdrop for the marketing card — light enough that the black
/// iPhone bezel pops against it instead of vanishing.
var cafeMarketingBackground: some View {
    LinearGradient(
        colors: [Color(red: 0.52, green: 0.36, blue: 0.24), Color(red: 0.27, green: 0.18, blue: 0.12)],
        startPoint: .top, endPoint: .bottom
    )
}

/// A full iPhone screen: full-bleed background + top clearance for the status
/// bar / notch + the app content. For V1, anything taller than the device is
/// clipped to what fits.
struct CafeScreen<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        ZStack(alignment: .top) {
            CafePalette.screen
            VStack(spacing: 0) {
                Spacer().frame(height: 56)
                content()
                Spacer(minLength: 0)
            }
        }
        .frame(width: 393, height: 852, alignment: .top)
        .clipped()
    }
}

struct CafeSectionHeader: View {
    var title: String
    var body: some View {
        Text(title)
            .font(.title2.bold())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Stand-in for `CoffeeItemview`: an icon chip + title on a rounded card.
struct CafeRow: View {
    var icon: String
    var title: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(CafePalette.icon).frame(width: 56, height: 56)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color(red: 0.25, green: 0.14, blue: 0.05))
            }
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal)
        .frame(height: 76)
        .background(CafePalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Screens (in navigation order)

/// 1. Stand-in for `HomeView`: tap the machine to start.
struct HomeScreen: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Dark Roasted Beans")
                .font(.title.bold())
                .foregroundStyle(.white)
            Text("Tap the machine to start")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.top, 8)

            Spacer()

            ZStack {
                Circle().fill(CafePalette.icon).frame(width: 156, height: 156)
                Image(systemName: "wave.3.forward")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(Color(red: 0.20, green: 0.11, blue: 0.04))
            }
            .frame(maxWidth: .infinity)

            Spacer()

            Text("How does this work")
                .font(.title3)
                .underline()
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(20)
    }
}

private func coffeeIcon(_ name: String) -> String {
    switch name {
    case "Ristretto": return "cup.and.saucer.fill"
    case "Espresso": return "mug.fill"
    default: return "takeoutbag.and.cup.and.straw.fill"
    }
}

/// 2. Stand-in for `CoffeesView`: pick your coffee style.
struct StyleScreen: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CafeSectionHeader(title: "Select your style")
            ForEach(CafeMock.coffee.types) { type in
                CafeRow(icon: coffeeIcon(type.name), title: type.name)
            }
        }
        .padding(20)
    }
}

private func sizeIcon(_ name: String) -> String {
    switch name {
    case "Tall": return "cup.and.saucer"
    case "Venti": return "cup.and.saucer.fill"
    default: return "takeoutbag.and.cup.and.straw.fill"
    }
}

/// 3. Stand-in for `CoffeeSizeView`: pick your size.
struct SizeScreen: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CafeSectionHeader(title: "Select your size")
            ForEach(CafeMock.coffee.sizes) { size in
                CafeRow(icon: sizeIcon(size.name), title: size.name)
            }
        }
        .padding(20)
    }
}

struct SubselectionRow: View {
    var name: String
    var isSelected: Bool

    var body: some View {
        HStack {
            Text(name).foregroundStyle(.white)
            Spacer()
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? CafePalette.icon : .white.opacity(0.4))
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }
}

/// 4. Stand-in for `ExtrasView`: customize sugar and milk, one pick per group.
struct ExtrasScreen: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            CafeSectionHeader(title: "Customize it")
            ForEach(CafeMock.coffee.extras) { extra in
                VStack(alignment: .leading, spacing: 8) {
                    Text(extra.labelText)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    VStack(spacing: 0) {
                        ForEach(Array(extra.subselections.enumerated()), id: \.element.id) { index, sub in
                            SubselectionRow(name: sub.name, isSelected: index == 0)
                        }
                    }
                    .background(CafePalette.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .padding(20)
    }
}
