import SwiftUI
import UIKit

/// The pieces every screen is built from.
///
/// They live here rather than next to the first screen that needs them, because
/// the library, the emulation settings, the per-title settings and the player's
/// own panels all want the same card, the same row, the same chip row and the
/// same cover. One definition, two arrangements — the size class decides the
/// arrangement, never the component.

// MARK: - Press feedback

/// Touch-down scales to 0.97 and springs back on release. Nothing scales on the
/// way up, so the gesture reads as physical rather than as a bounce.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = Design.Motion.pressScale

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            // iOS 14: the two-parameter `animation(_:value:)` is iOS 15, so the
            // animation is chosen here and applied to the whole change.
            .animation(configuration.isPressed ? Design.Motion.pressDown : Design.Motion.pressUp)
    }
}

/// One light tick when a control is touched, honouring the haptics setting the
/// emulation settings screen already owns.
enum DesignHaptics {
    private static let generator = UIImpactFeedbackGenerator(style: .light)

    static func prepare() {
        generator.prepare()
    }

    static func tap() {
        guard SettingsStore.shared.global.emulation.hapticsEnabled else { return }
        generator.impactOccurred()
    }
}

/// Attach to anything pressable that is not a `Button` with `PressableStyle`.
struct PressHaptic: ViewModifier {
    @State private var fired = false

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !fired else { return }
                    fired = true
                    DesignHaptics.tap()
                }
                .onEnded { _ in
                    fired = false
                }
        )
    }
}

extension View {
    /// One tick on touch-down for a control that is not a styled `Button`.
    func pressHaptic() -> some View { modifier(PressHaptic()) }
}

// MARK: - Card

/// A white card with a section header, optional explanation and a soft shadow.
///
/// Rows go inside; the hairline between them comes from `RowDivider`, so the
/// card does not draw separators it cannot position.
struct DesignCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.s) {
            VStack(alignment: .leading, spacing: Design.Space.xxs) {
                Text(title)
                    .font(Design.Fonts.section)
                    .foregroundColor(Design.Palette.ink)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(Design.Fonts.caption)
                        .foregroundColor(Design.Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .padding(Design.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Design.Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
        .designShadow(Design.Elevation.card)
    }
}

// MARK: - Row

/// A row: a title, an optional subtitle, and a control on the right.
///
/// When `isAvailable` is false the whole row greys out and stops taking touches,
/// and its subtitle becomes the explanation of what is missing. That is the one
/// way a placeholder is allowed to look in this app.
struct DesignRow<Control: View>: View {
    let title: String
    let subtitle: String?
    let isAvailable: Bool
    let control: Control

    init(_ title: String,
         subtitle: String? = nil,
         isAvailable: Bool = true,
         @ViewBuilder control: () -> Control) {
        self.title = title
        self.subtitle = subtitle
        self.isAvailable = isAvailable
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: Design.Space.m) {
            VStack(alignment: .leading, spacing: Design.Space.xxs) {
                Text(title)
                    .font(Design.Fonts.rowTitle)
                    .foregroundColor(isAvailable ? Design.Palette.ink : Design.Palette.secondaryInk)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(Design.Fonts.rowSubtitle)
                        .foregroundColor(Design.Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Design.Space.xs)
            control
                .opacity(isAvailable ? 1 : 0.45)
        }
        .padding(.vertical, Design.Space.s)
        .contentShape(Rectangle())
        .allowsHitTesting(isAvailable)
    }
}

extension DesignRow where Control == EmptyView {
    init(_ title: String, subtitle: String? = nil, isAvailable: Bool = true) {
        self.init(title, subtitle: subtitle, isAvailable: isAvailable) { EmptyView() }
    }
}

/// The hairline between two rows. A pixel, inset to the card's text margin.
struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Design.Palette.hairline)
            .frame(height: 1)
    }
}

// MARK: - Chip row

/// A horizontal set of choices where exactly one is selected.
///
/// The selected chip is an accent capsule and the change animates with the
/// selection spring, so moving the choice reads as the pill moving rather than as
/// two colours switching.
struct ChipRow: View {
    let options: [String]
    let selection: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: Design.Space.xxs) {
            ForEach(options.indices, id: \.self) { index in
                Button(action: { onSelect(index) }) {
                    Text(options[index])
                        .font(Design.Fonts.caption.weight(.semibold))
                        .foregroundColor(selection == index ? Color.white : Design.Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, Design.Space.s)
                        .frame(height: 32)
                        .background(
                            Capsule().fill(selection == index
                                           ? Design.Palette.accent
                                           : Design.Palette.hairline.opacity(0.55))
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .pressHaptic()
                .accessibilityAddTraits(selection == index ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white))
        .overlay(
            Capsule().stroke(Design.Palette.hairline, lineWidth: 1)
        )
        .animation(Design.Motion.selection)
        .fixedSize()
    }
}

// MARK: - Circular button

/// A 44 pt circle with a hairline edge, for the icon buttons beside the title.
struct CircleButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Design.Palette.ink)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Design.Palette.card))
                .overlay(Circle().stroke(Design.Palette.hairline, lineWidth: 1))
                .designShadow(Design.Elevation.cover)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .pressHaptic()
        .accessibilityLabel(label)
    }
}

// MARK: - Floating capsule bar

/// The navigation bar and any other floating strip: a capsule of blurred
/// material with a hairline, sitting over the page.
///
/// It is deliberately the only blurred layer a screen may have, and it must not
/// be inside anything that animates, or the blur is recomputed every frame.
struct FloatingCapsuleBar<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(
                BlurBackdrop(style: .systemMaterial)
                    .clipShape(Capsule())
                    .allowsHitTesting(false)
            )
            .overlay(
                Capsule().stroke(Design.Palette.hairline, lineWidth: 1)
                    .allowsHitTesting(false)
            )
            .designShadow(Design.Elevation.card)
    }
}

// MARK: - Cover cell

/// A game in the library: the artwork, its name, and one line about it.
///
/// The artwork is drawn at `aspect` because 3DS icons are square while a future
/// source may not be; the cell never assumes 1:1, it is told. When there is no
/// artwork the placeholder is the same size, so a grid never reflows as icons
/// decode.
///
/// `heroNamespace` is how the cell lends its artwork to a detail pane: both draw
/// the same geometry id, so opening a title grows the cover into the hero rather
/// than sliding a second copy of the picture in.
struct CoverCell: View {
    let artwork: UIImage?
    let name: String
    let meta: String
    var aspect: CGFloat = 1
    var heroNamespace: Namespace.ID? = nil
    var heroID: String = "cover"
    var heroSource: Bool = true
    var onOpen: () -> Void
    var onMenu: (() -> Void)?

    private var artworkLayer: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Design.Radius.cover, style: .continuous)
                .fill(Design.Palette.hairline.opacity(0.5))
            if let artwork = artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(Design.Space.xs)
            } else {
                Text(String(name.prefix(1)).uppercased())
                    .font(Design.Fonts.section)
                    .foregroundColor(Design.Palette.secondaryInk)
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.cover, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.cover, style: .continuous)
                .stroke(Design.Palette.hairline, lineWidth: 1)
                .allowsHitTesting(false)
        )
        .designShadow(Design.Elevation.cover)
        .contentShape(RoundedRectangle(cornerRadius: Design.Radius.cover, style: .continuous))
    }

    private var heroedArtwork: some View {
        Group {
            if let namespace = heroNamespace {
                artworkLayer
                    .matchedGeometryEffect(id: heroID, in: namespace, isSource: heroSource)
            } else {
                artworkLayer
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.xs) {
            Button(action: onOpen) {
                heroedArtwork
            }
            .buttonStyle(PressableStyle())
            .pressHaptic()
            .accessibilityLabel(name)

            HStack(alignment: .top, spacing: Design.Space.xs) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(Design.Fonts.cellName)
                        .foregroundColor(Design.Palette.ink)
                        .lineLimit(1)
                    Text(meta)
                        .font(Design.Fonts.cellMeta)
                        .foregroundColor(Design.Palette.secondaryInk)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let onMenu = onMenu {
                    Button(action: onMenu) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Design.Palette.secondaryInk)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Design.Palette.card))
                            .overlay(Circle().stroke(Design.Palette.hairline, lineWidth: 1))
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressableStyle())
                    .pressHaptic()
                    .accessibilityLabel("More options for \(name)")
                }
            }
        }
    }
}
