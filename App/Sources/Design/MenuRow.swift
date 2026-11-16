import SwiftUI

/// A setting with more choices than a row can hold: the value on the right, a
/// chevron, and the whole row opens the choices.
///
/// The panel is SwiftUI's own `Menu` around a `Picker`, not one of ours. With the
/// app declaring a light appearance, the system panel arrives light, right
/// beside the row, with the checkmark, the selection haptic and the anchoring
/// behaviour coming from the system rather than from code here that has to be
/// kept in step with it. It is also the panel VoiceOver already knows.
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
            DesignRow(title, subtitle: subtitle) {
                HStack(spacing: Design.Space.xxs) {
                    Text(currentTitle)
                        .font(Design.Fonts.caption.weight(.semibold))
                        .foregroundColor(selection == nil ? Design.Palette.secondaryInk : Design.Palette.ink)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Design.Palette.secondaryInk)
                }
            }
            // A row with a subtitle is taller than this on its own; a short one
            // would not be, and every row in this app is at least 44 pt.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(currentTitle)
        .accessibilityHint("Opens the choices")
        .accessibilityAddTraits(.isButton)
    }
}
