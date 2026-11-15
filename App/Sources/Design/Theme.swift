import SwiftUI
import UIKit

/// The design system: every colour, radius, shadow, type size, spacing step and
/// animation in the app comes from here.
///
/// The era being matched is the one just before Liquid Glass — flat surfaces with
/// real depth: a near-white page, white cards with a soft shadow, hairline
/// separators, blur only behind panels that float, and one accent. Nothing in
/// here is a gradient, a glow or a looping animation, because the frames this app
/// spends on decoration are frames the emulator does not get.
///
/// The player screen is the one exception and stays dark: a light page behind a
/// 3DS picture is a distraction and it dims the picture.
enum Design {

    // MARK: - Palette

    enum Palette {
        /// The page. Everything is drawn on this.
        static let background = hex(0xF5F5F7)
        /// Cards, rows and anything that should sit above the page.
        static let card = Color.white
        /// Primary text.
        static let ink = hex(0x111114)
        /// Subtitles, metadata, anything secondary.
        static let secondaryInk = hex(0x8A8A8E)
        /// Separators and button outlines. One pixel, never a fill.
        static let hairline = hex(0xE6E6EA)
        /// The only accent: selection, active pill, links.
        static let accent = hex(0x7B6CF6)
        /// The accent at low strength, for the inside of a selected pill's row.
        static let accentSoft = hex(0x7B6CF6).opacity(0.12)
        /// Confirm buttons only. Never decoration.
        static let positive = hex(0x34C759)

        /// The player screen. Dark always, light mode or not.
        static let playerBackground = Color.black
        static let playerHudFill = Color.black.opacity(0.62)
        static let playerHudStroke = Color.white.opacity(0.10)
        static let playerInk = Color.white

        private static func hex(_ value: UInt32) -> Color {
            Color(.sRGB,
                  red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255,
                  opacity: 1)
        }
    }

    // MARK: - Radii

    enum Radius {
        /// Cover art and the cells that hold it.
        static let cover: CGFloat = 20
        /// Cards and panels.
        static let card: CGFloat = 24
        /// Pills and buttons are capsules; this is only for a rounded rect that
        /// has to fake one.
        static let capsule: CGFloat = 999
    }

    // MARK: - Elevation

    /// Shadows that make a flat surface sit above the page. Two of them, and no
    /// more: if a third is needed the layout is wrong.
    enum Elevation {
        static let card = Shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 2)
        static let cover = Shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 1)

        struct Shadow {
            let color: Color
            let radius: CGFloat
            let x: CGFloat
            let y: CGFloat
        }
    }

    // MARK: - Type

    /// Six sizes. A screen that needs a seventh is a screen with a hierarchy
    /// problem, so add one here rather than inline.
    enum Fonts {
        /// Screen title: "Games", "Settings".
        static let title = Font.system(size: 34, weight: .bold)
        /// Section header inside a page: "Graphics".
        static let section = Font.system(size: 20, weight: .bold)
        /// A row's label.
        static let rowTitle = Font.system(size: 17, weight: .semibold)
        /// A row's explanation.
        static let rowSubtitle = Font.system(size: 15)
        /// A cover cell's name.
        static let cellName = Font.system(size: 17, weight: .semibold)
        /// A cover cell's size or system.
        static let cellMeta = Font.system(size: 15)
        /// The smallest text in the app.
        static let caption = Font.system(size: 13)
        /// The player HUD: digits that must not shift as they tick.
        static let hud = Font.system(size: 9.5, weight: .medium, design: .monospaced)
    }

    // MARK: - Spacing

    /// One scale, multiples of four. Screen side margin is `l`.
    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        /// The margin every screen uses left and right.
        static let sideMargin: CGFloat = l
    }

    // MARK: - Motion

    /// Four springs and one fade. Every moving thing in the app uses one of
    /// these, so two screens never move to different rhythms.
    enum Motion {
        /// A pill moving between segments, a tab switching.
        static let selection = Animation.interactiveSpring(response: 0.34, dampingFraction: 0.86)
        /// A control settling under the finger.
        static let pressDown = Animation.spring(response: 0.18, dampingFraction: 0.9)
        /// The same control letting go. Slightly slower than the way down.
        static let pressUp = Animation.spring(response: 0.26, dampingFraction: 0.86)
        /// A panel or sheet arriving over the page.
        static let panel = Animation.interactiveSpring(response: 0.42, dampingFraction: 0.88)
        /// The dim behind a panel. Always paired with `panel`, started together.
        static let backdrop = Animation.easeOut(duration: 0.25)
        /// A row's one-shot entrance.
        static let entrance = Animation.spring(response: 0.46, dampingFraction: 0.9)

        /// Seconds between two entrance rows.
        static let entranceStagger: Double = 0.02
        /// How far a row rises as it fades in.
        static let entranceRise: CGFloat = 8
        /// How far a pressed control scales down.
        static let pressScale: CGFloat = 0.97
    }
}

extension View {
    /// The one shadow a card or a cover may ask for.
    func designShadow(_ shadow: Design.Elevation.Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}
