import SwiftUI

/// A setting with more choices than a row can hold: the value on the right, a
/// chevron, and the whole row opens the choices.
///
/// The panel is `SelectionMenuOverlay` rather than SwiftUI's `Menu`. The system
/// menu takes the appearance the app declares and centres itself over the card,
/// which on this light design arrived as a dark sheet across the middle of the
/// page — and neither of those is something a `Menu` can be told otherwise on
/// iOS 14. This row's panel is light, hangs under the value it belongs to, and
/// leaves the row and its subtitle readable while it is open.
///
/// `selection` is nil when nothing was ever chosen. The row then reads
/// `defaultTitle` and the panel ticks that same line, so "never chosen" is a
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

    @State private var valueFrame: CGRect = .zero

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

    /// Which option is in force, or nil when nothing was chosen.
    private var chosen: Int? {
        guard let selection = selection else { return nil }
        return options.firstIndex { $0.value == selection }
    }

    private var currentTitle: String {
        guard let index = chosen else { return defaultTitle }
        return options[index].title
    }

    var body: some View {
        Button(action: present) {
            DesignRow(title, subtitle: subtitle) {
                value
            }
            // A row with a subtitle is taller than this on its own; a short one
            // would not be, and every row in this app is at least 44 pt.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.995))
        .pressHaptic()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(currentTitle)
        .accessibilityHint("Opens the choices")
        .accessibilityAddTraits(.isButton)
    }

    private var value: some View {
        HStack(spacing: Design.Space.xxs) {
            Text(currentTitle)
                .font(Design.Fonts.caption.weight(.semibold))
                .foregroundColor(selection == nil ? Design.Palette.secondaryInk : Design.Palette.ink)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Design.Palette.secondaryInk)
        }
        // The panel hangs from this view, so its position on screen is measured
        // as it is drawn.
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { valueFrame = geometry.frame(in: .global) }
                    .onChange(of: geometry.frame(in: .global)) { frame in
                        valueFrame = frame
                    }
            }
        )
    }

    private func present() {
        let titles = [defaultTitle] + options.map { $0.title }
        SelectionMenuCenter.shared.present(rowTitle: title,
                                           items: titles,
                                           selection: chosen.map { $0 + 1 } ?? 0,
                                           anchor: valueFrame) { index in
            if index == 0 {
                onSelect(nil)
            } else {
                onSelect(options[index - 1].value)
            }
        }
    }
}
