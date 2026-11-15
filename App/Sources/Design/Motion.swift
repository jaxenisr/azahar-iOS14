import SwiftUI

/// The motion vocabulary, in one place.
///
/// Four springs and one fade, and nothing that runs on its own. A layer that
/// animates forever spends the frames the emulator needs, so nothing here loops,
/// pulses or shimmers: everything starts because something was touched and stops
/// when it settles.

// MARK: - Entrance

/// A row's one-shot entrance: it fades and rises 8 pt, once, with a 20 ms stagger
/// against its neighbours. It never replays on a state change, because a list that
/// re-animates every time a value changes is a list that feels broken.
struct Entrance: ViewModifier {
    let index: Int
    @State private var settled = false

    func body(content: Content) -> some View {
        content
            .opacity(settled ? 1 : 0)
            .offset(y: settled ? 0 : Design.Motion.entranceRise)
            .onAppear {
                guard !settled else { return }
                // Long lists should not take a second to arrive: the stagger is
                // capped so the last row is never far behind the first.
                let step = min(index, 12)
                let delay = Double(step) * Design.Motion.entranceStagger
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(Design.Motion.entrance) {
                        settled = true
                    }
                }
            }
    }
}

extension View {
    /// Fade and rise once, as the `index`-th row of a screen.
    func entrance(_ index: Int) -> some View {
        modifier(Entrance(index: index))
    }
}

// MARK: - Scroll offset

/// How far a scroll view's content has travelled, published upwards so a title
/// can collapse without a navigation bar doing it for us.
struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Put this at the very top of a scroll view's content. It has no height, so it
/// cannot move anything, and it reports `-minY` in the named "screen" space.
struct ScrollOffsetReader: View {
    var body: some View {
        GeometryReader { geometry in
            Color.clear.preference(key: ScrollOffsetKey.self,
                                   value: -geometry.frame(in: .named("screen")).minY)
        }
        .frame(height: 0)
    }
}

extension View {
    /// The coordinate space `ScrollOffsetReader` measures against.
    func screenScrollSpace() -> some View {
        coordinateSpace(name: "screen")
    }
}

// MARK: - Collapsing title

/// A large title that shrinks as the page scrolls under it: 34 pt at rest, 22 pt
/// once 48 pt has gone by, with the subtitle fading out on the way. Hand-built,
/// because a navigation bar would bring its own bar, its own blur and its own
/// back button to a page that wants none of them.
struct CollapsingTitle<Accessory: View>: View {
    let title: String
    let subtitle: String
    let offset: CGFloat
    let accessory: Accessory

    /// 0 at rest, 1 once the page is scrolled past the collapse distance.
    private var progress: CGFloat {
        min(max(offset / 48, 0), 1)
    }

    init(title: String,
         subtitle: String,
         offset: CGFloat,
         @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.subtitle = subtitle
        self.offset = offset
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: Design.Space.m) {
            VStack(alignment: .leading, spacing: Design.Space.xxs) {
                Text(title)
                    .font(.system(size: 34 - 12 * progress, weight: .bold))
                    .foregroundColor(Design.Palette.ink)
                Text(subtitle)
                    .font(Design.Fonts.rowSubtitle)
                    .foregroundColor(Design.Palette.secondaryInk)
                    .opacity(Double(1 - progress))
                    .frame(height: 20 * (1 - progress), alignment: .top)
                    .clipped()
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Design.Space.xs)
            accessory
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Design.Space.sideMargin)
        .padding(.top, Design.Space.l)
        .padding(.bottom, Design.Space.xs)
    }
}

extension CollapsingTitle where Accessory == EmptyView {
    init(title: String, subtitle: String, offset: CGFloat) {
        self.init(title: title, subtitle: subtitle, offset: offset) { EmptyView() }
    }
}
