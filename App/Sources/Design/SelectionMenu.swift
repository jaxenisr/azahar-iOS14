import SwiftUI

/// The row whose choices are open, and the choices themselves.
///
/// One menu is open at a time for the whole app, so the state lives here instead
/// of in each row: the panel is drawn at the top of the view tree, above every
/// card, so no card's clip can cut it and no scroll view can carry it away from
/// the row it belongs to.
///
/// This is a panel of the app's own rather than SwiftUI's `Menu`. The system menu
/// takes its colours from the appearance the app declares and always centres
/// itself over the presenting view, so on this light design it arrived as a dark
/// sheet floating across the middle of a card — wrong on both counts, and not
/// something a `Menu` can be told otherwise on iOS 14.
final class SelectionMenuCenter: ObservableObject {
    /// One line in the panel.
    struct Item: Identifiable {
        let id: Int
        let title: String
    }

    static let shared = SelectionMenuCenter()

    @Published private(set) var isPresented = false
    /// The row's own label, so the panel can name itself to VoiceOver.
    @Published private(set) var rowTitle = ""
    @Published private(set) var items: [Item] = []
    /// The index of the ticked line. The untouched state is index 0, never nil:
    /// a menu always shows which choice is in force.
    @Published private(set) var selection = 0
    /// Where the row's value sits on screen, in global coordinates.
    @Published private(set) var anchor: CGRect = .zero

    private var onChoose: ((Int) -> Void)?

    private init() {}

    func present(rowTitle: String,
                 items: [String],
                 selection: Int,
                 anchor: CGRect,
                 onChoose: @escaping (Int) -> Void) {
        self.rowTitle = rowTitle
        self.items = items.enumerated().map { Item(id: $0.offset, title: $0.element) }
        self.selection = min(max(selection, 0), max(items.count - 1, 0))
        self.anchor = anchor
        self.onChoose = onChoose
        withAnimation(Design.Motion.panel) {
            isPresented = true
        }
    }

    func choose(_ index: Int) {
        guard isPresented else { return }
        let handler = onChoose
        dismiss()
        DesignHaptics.tap()
        handler?(index)
    }

    func dismiss() {
        guard isPresented else { return }
        onChoose = nil
        withAnimation(Design.Motion.panel) {
            isPresented = false
        }
    }
}

/// Where the choices are drawn: once, above everything, for the whole app.
///
/// It closes on a tap outside, closes on a selection, and never covers the row
/// that opened it — it hangs under the row's value, spans the value column rather
/// than the screen, and scrolls inside itself when there are more choices than
/// there is room below.
struct SelectionMenuOverlay: View {
    @ObservedObject private var center = SelectionMenuCenter.shared

    /// One line's height: 44 pt, the smallest target this app allows anywhere.
    private static let itemHeight: CGFloat = 44
    /// The panel never leans on the screen edge.
    private static let edge: CGFloat = 12
    /// Between the row's value and the top of the panel.
    private static let gap: CGFloat = 6
    /// Below this much room, a panel is not worth opening downwards.
    private static let minimumRoom: CGFloat = 140

    var body: some View {
        GeometryReader { geometry in
            if center.isPresented {
                let origin = geometry.frame(in: .global).origin
                ZStack(alignment: .topLeading) {
                    // Tap outside to close. Light enough to read as a shadow
                    // under the panel rather than as a dimmed page.
                    Design.Palette.ink.opacity(0.06)
                        .contentShape(Rectangle())
                        .onTapGesture { center.dismiss() }
                        .transition(.opacity)

                    panel(in: geometry.size,
                          anchor: CGRect(x: center.anchor.minX - origin.x,
                                         y: center.anchor.minY - origin.y,
                                         width: center.anchor.width,
                                         height: center.anchor.height))
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .topTrailing)))
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Geometry

    /// The panel's frame for the current anchor: trailing edge under the value,
    /// as wide as the value column plus its air, and never taller than the room
    /// under the row — a longer list scrolls inside the panel instead.
    private func panel(in size: CGSize, anchor: CGRect) -> some View {
        let width = min(max(anchor.width + Design.Space.xxl, 208), 288)
        var x = anchor.maxX - width
        x = min(max(x, SelectionMenuOverlay.edge), size.width - width - SelectionMenuOverlay.edge)

        let content = CGFloat(center.items.count) * SelectionMenuOverlay.itemHeight
            + CGFloat(max(center.items.count - 1, 0))
        let below = size.height - (anchor.maxY + SelectionMenuOverlay.gap) - SelectionMenuOverlay.edge
        let above = anchor.minY - SelectionMenuOverlay.gap - SelectionMenuOverlay.edge
        // Under the row, as asked. Above only when there is no usable room there,
        // so a row near the bottom still gets its choices.
        let goesBelow = below >= SelectionMenuOverlay.minimumRoom || below >= above
        let room = goesBelow ? below : above
        let height = min(content, max(room, SelectionMenuOverlay.itemHeight * 2))
        let y = goesBelow
            ? anchor.maxY + SelectionMenuOverlay.gap
            : anchor.minY - SelectionMenuOverlay.gap - height

        return ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(center.items) { item in
                    line(item)
                    if item.id < center.items.count - 1 {
                        // Hairlines between lines only: never at the panel's edge.
                        Rectangle()
                            .fill(Design.Palette.hairline)
                            .frame(height: 1)
                            .padding(.leading, Design.Space.m)
                    }
                }
            }
        }
        .frame(width: width, height: height)
        .background(
            ZStack {
                BlurBackdrop(style: .systemThinMaterialLight)
                Color.white.opacity(0.72)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
                .stroke(Design.Palette.hairline, lineWidth: 1)
                .allowsHitTesting(false)
        )
        .designShadow(Design.Elevation.card)
        // The page is light and so is this, whatever the device's appearance is.
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(center.rowTitle)
        .offset(x: x, y: max(y, SelectionMenuOverlay.edge))
    }

    private func line(_ item: SelectionMenuCenter.Item) -> some View {
        let isSelected = center.selection == item.id
        return Button(action: { center.choose(item.id) }) {
            HStack(spacing: Design.Space.xs) {
                Text(item.title)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(Design.Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: Design.Space.xxs)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Design.Palette.ink)
                }
            }
            .padding(.horizontal, Design.Space.m)
            .frame(height: SelectionMenuOverlay.itemHeight)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
