import SwiftUI

/// A setting with more choices than a row can hold: the value on the right, a
/// chevron, and the value opens the choices.
///
/// The panel is SwiftUI's own `Menu`, so its material, its checkmark, the
/// selection haptic and the presentation are the system's.
///
/// Where it appears is not ours to choose: on iOS 14 a `UIMenu` is placed
/// relative to the centre of the view it is attached to, and there is no anchor
/// API. Attached to the whole row, the panel opened in the middle of the card
/// over the rows below; attached to the value, it opens where the value is,
/// which is where this design wants it. The trade is deliberate and is the one
/// Apple's menu cannot avoid: the value column is the target, not the row's
/// title.
///
/// The target is still a comfortable one — the full 44 pt row height and at
/// least 100 pt wide, ending at the chevron, with a rectangle hit shape — so it
/// reads as the value and is easy to hit.
///
/// `selection` is nil when nothing was ever chosen. The row then reads
/// `defaultTitle` and the picker ticks that same line, so "never chosen" is a
/// state the app can show. Choosing that line again reports nil rather than
/// writing the default into storage as if it had been picked.
struct MenuSettingRow<Value: Hashable>: View {
    /// One choice and the text it shows in the row and the panel.
    struct Option {
        let title: String
        let value: Value
    }

    let title: String
    let subtitle: String?
    /// What the row and the panel call the untouched state: `Default` everywhere,
    /// and `Automatic` for a setting whose default is the core choosing for you.
    let defaultTitle: String
    let options: [Option]
    let selection: Value?
    let onSelect: (Value?) -> Void

    init(title: String,
         subtitle: String? = nil,
         defaultTitle: String = "Default",
         options: [Option],
         selection: Value?,
         onSelect: @escaping (Value?) -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.defaultTitle = defaultTitle
        self.options = options
        self.selection = selection
        self.onSelect = onSelect
    }

    private var currentTitle: String {
        guard let selection = selection,
              let match = options.first(where: { $0.value == selection }) else {
            return defaultTitle
        }
        return match.title
    }

    var body: some View {
        DesignRow(title, subtitle: subtitle) {
            Menu {
                // The untouched state is the first line and carries the tick when
                // nothing was chosen, so the panel always shows what is in force.
                Picker(title,
                       selection: Binding(get: { selection },
                                          set: { onSelect($0) })) {
                    Text(defaultTitle).tag(Optional<Value>.none)
                    ForEach(options, id: \.value) { option in
                        Text(option.title).tag(Optional(option.value))
                    }
                }
            } label: {
                HStack(spacing: Design.Space.xxs) {
                    Text(currentTitle)
                        .font(Design.Fonts.caption.weight(.semibold))
                        .foregroundColor(selection == nil ? Design.Palette.secondaryInk : Design.Palette.ink)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Design.Palette.secondaryInk)
                }
                // This frame is what the panel hangs from, and what the finger
                // has to hit: the whole row's height, at least 100 pt wide, ending
                // at the chevron.
                .frame(minWidth: 100, minHeight: 44, alignment: .trailing)
                .contentShape(Rectangle())
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(currentTitle)
            .accessibilityHint("Opens the choices")
            .accessibilityAddTraits(.isButton)
        }
    }
}
