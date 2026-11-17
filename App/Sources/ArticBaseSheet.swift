import SwiftUI

/// The Games page's streaming sheet: one address, one button, and what the core
/// does with it.
///
/// It is a light sheet like every other panel in this app. What it starts is not a
/// second player: the player is given an `articbase://` location instead of a file
/// path, so the HUD, the controls, save states and the amiibo sheet are the ones a
/// local title already gets.
struct ArticBaseSheet: View {
    let coreDirectory: URL
    let onClose: () -> Void

    @ObservedObject private var store = SettingsStore.shared
    @State private var text = ArticAddress.remembered?.display ?? ""
    @State private var message: String?
    /// The running stream, if one was started from this sheet.
    @State private var session: PlaybackSession?

    private var address: ArticAddress? { ArticAddress.parse(text) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Space.l) {
                    column {
                        SettingsCard("Address", subtitle: "Where the console is on this network") {
                            HStack(spacing: Design.Space.s) {
                                Image(systemName: "wifi")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Design.Palette.secondaryInk)
                                TextField("192.168.1.5", text: $text, onCommit: connect)
                                    .font(.system(size: 15, design: .monospaced))
                                    .foregroundColor(Design.Palette.ink)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                            }
                            .frame(minHeight: 44)

                            if let message = message {
                                RowDivider()
                                Text(message)
                                    .font(Design.Fonts.caption)
                                    .foregroundColor(Color.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            RowDivider()

                            Button(action: connect) {
                                DesignRow("Connect", subtitle: connectLine) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(Design.Palette.secondaryInk)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PressableStyle(scale: 0.99))
                            .pressHaptic()
                        }
                        .entrance(0)

                        SettingsCard("How this works") {
                            Text("Artic Base runs on the console and hands its open title to this app over the network: the picture, the sound, and the game data as the game asks for it. Nothing is copied into the library — the library is files this iPad holds. The console decides which title streams, so all this screen needs is where to find it, and the first connection asks for local network access. A streamed session keeps one save-state slot per address, because the title id belongs to the console rather than to a file here.")
                                .font(Design.Fonts.caption)
                                .foregroundColor(Design.Palette.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .entrance(1)
                    }
                }
                .padding(.top, Design.Space.m)
                .padding(.bottom, Design.Space.xxl * 2)
            }
        }
        .background(Design.Palette.background.ignoresSafeArea())
        .fullScreenCover(item: $session) { session in
            PlaybackScreen(session: session)
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .center, spacing: Design.Space.m) {
            VStack(alignment: .leading, spacing: Design.Space.xxs) {
                Text("Artic Base")
                    .font(Design.Fonts.title)
                    .foregroundColor(Design.Palette.ink)
                Text("Stream a title from a console on your network")
                    .font(Design.Fonts.rowSubtitle)
                    .foregroundColor(Design.Palette.secondaryInk)
            }
            Spacer(minLength: Design.Space.xs)
            CircleButton(symbol: "xmark", label: "Close") {
                onClose()
            }
        }
        .padding(.horizontal, Design.Space.sideMargin)
        .padding(.top, Design.Space.l)
        .padding(.bottom, Design.Space.xs)
    }

    private func column<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, Design.Space.sideMargin)
    }

    /// The line under Connect: what pressing it will actually do.
    private var connectLine: String {
        guard let address = address else {
            return "An address first: 192.168.1.5, or 192.168.1.5:5543 for a server on another port"
        }
        return "Start the stream from \(address.display)"
    }

    // MARK: - Action

    private func connect() {
        guard let address = address else {
            message = "This app can read a host name or an IPv4 address, optionally with a port. Anything else would go to the core and come back ten seconds later as a failed load."
            return
        }
        message = nil
        text = address.display
        address.remember()
        let entry = address.entry
        session = PlaybackSession(game: entry,
                                  coreDirectory: coreDirectory,
                                  settings: store.settings(for: entry.id))
    }
}
