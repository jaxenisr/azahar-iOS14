import SwiftUI

/// One place for the app's surfaces, type and spacing.
///
/// The library, the game page, the settings screens and the diagnostic sheet
/// each used to draw their own cards: three different radii, four opacities of
/// white for the same idea, and two side margins. Everything asks here now, so
/// a card looks the same wherever it appears and nothing is off by a point.
///
/// This is the dark theme the app shipped with. It keeps every value it has while
/// the design phases move screens to `Design` one at a time; the file is renamed
/// from `Theme.swift` so the single file of that name is the new token set.
enum Theme {
    // MARK: Base surfaces

    static let background = Color(red: 0.04, green: 0.05, blue: 0.07)
    static let backgroundSpotlight = Color(red: 0.05, green: 0.06, blue: 0.08)

    // MARK: Cards

    static let cardRadius: CGFloat = 24
    static let cardFill = Color.white.opacity(0.055)
    static let cardStroke = Color.white.opacity(0.07)
    static let cardPadding: CGFloat = 18

    // MARK: Capsules

    static let chipHeight: CGFloat = 32
    static let chipFill = Color.white.opacity(0.1)
    static let chipSelectedFill = Color.white.opacity(0.88)
    static let chipInk = Color.black
    static let chipText = Color.white.opacity(0.85)
    static let chipFont = Font.system(size: 12, weight: .semibold)

    // MARK: Layout

    static let sideMargin: CGFloat = 26
    static let cardSpacing: CGFloat = 18
    static let sectionSpacing: CGFloat = 18
    static let rowHeight: CGFloat = 40
    /// Clearance under scrolling content, so the floating tab bar never sits on
    /// top of a last row and no screen ends in a band it cannot use.
    static let bottomClearance: CGFloat = 104

    // MARK: Type

    static let title = Font.system(size: 34, weight: .bold)
    static let subtitle = Font.system(size: 12)
    static let sectionTitle = Font.system(size: 11, weight: .semibold)
    static let rowTitle = Font.system(size: 14, weight: .medium)
    static let detail = Font.system(size: 11)
    static let monospaced = Font.system(size: 12, design: .monospaced)
    static let monospacedSmall = Font.system(size: 11, design: .monospaced)

    // MARK: Ink

    static let primaryInk = Color.white
    static let secondaryInk = Color.white.opacity(0.55)
    static let tertiaryInk = Color.white.opacity(0.42)
}

/// Press feedback for anything shaped like a card, a tile or a chip: it settles
/// under the finger instead of flashing.
struct CardButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.98
    var pressedOpacity: Double = 0.7

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(.easeOut(duration: 0.14))
    }
}

extension View {
    /// The card surface used everywhere: one radius, one fill, one hairline.
    /// Both decoration layers ignore touches, so a card never eats a tap meant
    /// for something inside it.
    func cardSurface(radius: CGFloat = Theme.cardRadius) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Theme.cardFill)
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Theme.cardStroke, lineWidth: 1)
                .allowsHitTesting(false)
        )
    }

    /// The app's one shape for a small button or a value: a capsule that owns
    /// its whole area, so its hit target is the capsule and not the text in it.
    func chipSurface(selected: Bool = false, height: CGFloat = Theme.chipHeight) -> some View {
        frame(height: height)
            .background(Capsule().fill(selected ? Theme.chipSelectedFill : Theme.chipFill))
            .contentShape(Capsule())
    }
}
