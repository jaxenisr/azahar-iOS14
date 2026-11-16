import SwiftUI

/// A setting with more choices than a row can hold: the value it is on, a chevron,
/// and the whole row opens the choices.
///
/// It is SwiftUI's own `Menu` around a `Picker`, not a panel of our own. That is a
/// deliberate choice rather than laziness: the frosted panel, the checkmark beside
/// the current choice, the selection haptic and the way the panel anchors under
/// the row all come from the system, and a hand-built panel would have to earn its
/// place by looking better than that. It does not need to — this row is inside a
/// card, which is the one place a system panel already belongs.
///
/// The label is the row itself, not a chip on its right, so the tap target is the
/// whole row and a tap anywhere in it opens the choices. `DesignRow` already draws
/// its own `contentShape`, and the 44 pt minimum is set here because a row with a
/// subtitle is taller than that on its own but a short one would not be.
struct MenuSettingRow<Value: Hashable>: View {
    /// One choice and the text it shows in the row and the panel.
    struct Option {
        let title: String
        let value: Value
    }

    let title: String
    let subtitle: String?
    let options: [Option]
    let selection: Value
    let onSelect: (Value) -> Void

    init(title: String,
         subtitle: String? = nil,
         options: [Option],
         selection: Value,
         onSelect: @escaping (Value) -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.options = options
        self.selection = selection
        self.onSelect = onSelect
    }

    private var current: String {
        options.first { $0.value == selection }?.title ?? ""
    }

    var body: some View {
        Menu {
            Picker(title,
                   selection: Binding(get: { selection },
                                      set: { onSelect($0) })) {
                ForEach(options, id: \.value) { option in
                    Text(option.title).tag(option.value)
                }
            }
        } label: {
            DesignRow(title, subtitle: subtitle) {
                HStack(spacing: Design.Space.xxs) {
                    Text(current)
                        .font(Design.Fonts.caption.weight(.semibold))
                        .foregroundColor(Design.Palette.ink)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Design.Palette.secondaryInk)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(current)
        .accessibilityHint("Opens the choices")
        .accessibilityAddTraits(.isButton)
    }
}
