import SwiftUI
import UniformTypeIdentifiers

/// The player's amiibo sheet: what the reader is doing, the dumps this app
/// holds, and the one action that matters — hand a tag over while the game is
/// asking for one.
///
/// It is a light sheet like every other panel in the app. The player behind it is
/// the only dark surface.
struct AmiiboScreen: View {
    let coreDirectory: URL
    let gameTitle: String
    let onClose: () -> Void

    @State private var tags: [AmiiboTag] = []
    @State private var state: AmiiboState = .unavailable
    /// The tag this sheet handed over, when it knows which one.
    @State private var loaded: AmiiboTag?
    @State private var message: String?
    @State private var showsImporter = false

    /// The reader's state changes underneath the sheet: the game opens its
    /// amiibo menu, or the core drops a tag after its own timeout. So it is read
    /// again every second while this is on screen, rather than once on appear.
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Space.l) {
                    column {
                        SettingsCard("Reader", subtitle: stateLine) {
                            InfoLine("Tag", loadedName)
                            if state == .loaded {
                                RowDivider()
                                Button(action: remove) {
                                    DesignRow("Remove this tag",
                                              subtitle: "The game sees the tag leave, as if the figure were lifted off") {
                                        Image(systemName: "eject")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(Design.Palette.secondaryInk)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(PressableStyle(scale: 0.99))
                                .pressHaptic()
                            }
                        }
                        .entrance(0)

                        if let message = message {
                            SettingsCard("Last attempt") {
                                Text(message)
                                    .font(Design.Fonts.caption)
                                    .foregroundColor(Design.Palette.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .entrance(1)
                        }

                        SettingsCard("Your tags",
                                     subtitle: "Documents/Azahar/amiibo — a folder this app keeps, holding one .bin per figure") {
                            if tags.isEmpty {
                                Text("No tags yet. Import a dump and it lands here.")
                                    .font(Design.Fonts.caption)
                                    .foregroundColor(Design.Palette.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                ForEach(Array(tags.enumerated()), id: \.element.id) { index, tag in
                                    if index > 0 {
                                        RowDivider()
                                    }
                                    Button(action: { load(tag) }) {
                                        DesignRow(tag.displayName, subtitle: tag.sizeDescription) {
                                            Image(systemName: loaded?.id == tag.id ? "checkmark" : "chevron.right")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(loaded?.id == tag.id
                                                                 ? Design.Palette.accent
                                                                 : Design.Palette.secondaryInk)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(PressableStyle(scale: 0.99))
                                    .pressHaptic()
                                    .accessibilityHint(canLoad ? "Loads this tag into the running game"
                                                               : "The game is not asking for a tag yet")
                                }
                            }

                            RowDivider()

                            Button(action: { showsImporter = true }) {
                                DesignRow("Import from Files",
                                          subtitle: "A .bin dump of one amiibo, exactly \(AmiiboTag.tagSize) bytes") {
                                    Image(systemName: "square.and.arrow.down")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(Design.Palette.secondaryInk)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PressableStyle(scale: 0.99))
                            .pressHaptic()
                        }
                        .entrance(1)

                        SettingsCard("How this works") {
                            Text("The core reads a tag from a file, and only while the running game is scanning for one: open the game's amiibo menu first. What you pick here is copied into this app's folder, and the core writes an in-game change back into that copy, so your own dump is only ever read. A dump that is encrypted and has no NFC keys on the device is loaded read-only — the core's own rule. Nothing about an amiibo is stored anywhere else, and a tag leaves on its own after the core's timeout.")
                                .font(Design.Fonts.caption)
                                .foregroundColor(Design.Palette.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .entrance(2)
                    }
                }
                .padding(.top, Design.Space.m)
                .padding(.bottom, Design.Space.xxl * 2)
            }
        }
        .background(Design.Palette.background.ignoresSafeArea())
        .onAppear(perform: refresh)
        .onReceive(tick) { _ in refresh() }
        .fileImporter(isPresented: $showsImporter,
                      allowedContentTypes: [.item],
                      onCompletion: importTag)
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .center, spacing: Design.Space.m) {
            VStack(alignment: .leading, spacing: Design.Space.xxs) {
                Text("Amiibo")
                    .font(Design.Fonts.title)
                    .foregroundColor(Design.Palette.ink)
                Text(gameTitle)
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

    // MARK: - Words

    private var stateLine: String {
        switch state {
        case .unavailable:
            return "This title has no NFC service, so there is nothing to read a tag into"
        case .waiting:
            return "A game is running and has not asked for a tag"
        case .scanning:
            return "The game is waiting for a tag"
        case .loaded:
            return "A tag is on the reader"
        }
    }

    private var loadedName: String {
        guard state == .loaded else { return "none" }
        if let loaded = loaded {
            return loaded.displayName
        }
        return "a tag loaded earlier"
    }

    /// The core accepts a tag only while the game is scanning and the reader is
    /// empty; both are the core's rules, so the row says which one is in the way.
    private var canLoad: Bool {
        state == .scanning
    }

    // MARK: - Actions

    private func refresh() {
        state = AmiiboLibrary.state
        if state != .loaded {
            loaded = nil
        }
        tags = AmiiboLibrary.tags(coreDirectory: coreDirectory)
    }

    private func load(_ tag: AmiiboTag) {
        guard tag.isTagSized else {
            message = "\(tag.displayName) is \(tag.byteCount) bytes. The core reads exactly \(AmiiboTag.tagSize), the size of one NTAG215 dump, and refuses anything else."
            return
        }
        guard state == .scanning else {
            message = state == .loaded
                ? "A tag is already on the reader. Remove it first."
                : "The game is not asking for a tag. Open its amiibo menu, then tap the tag again."
            return
        }
        guard AmiiboLibrary.load(tag) else {
            message = "The core refused \(tag.displayName). The game may have stopped asking for a tag in the meantime."
            return
        }
        loaded = tag
        message = nil
        refresh()
    }

    private func remove() {
        AmiiboLibrary.remove()
        loaded = nil
        message = nil
        refresh()
    }

    private func importTag(_ result: Result<URL, Error>) {
        switch result {
        case .success(let source):
            do {
                let tag = try AmiiboLibrary.importTag(from: source, coreDirectory: coreDirectory)
                message = tag.isTagSized
                    ? "\(tag.displayName) is in the folder. Pick it while the game is asking for a tag."
                    : "\(tag.displayName) is \(tag.byteCount) bytes. The core reads exactly \(AmiiboTag.tagSize), so this one will be refused."
            } catch {
                message = "That file could not be copied: \(error.localizedDescription)"
            }
        case .failure(let error):
            message = error.localizedDescription
        }
        refresh()
    }
}

/// A label and a right-aligned value, the shape the info rows in the texture
/// pack sheet use.
private struct InfoLine: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Space.xs) {
            Text(label)
                .font(Design.Fonts.caption)
                .foregroundColor(Design.Palette.secondaryInk)
            Spacer(minLength: Design.Space.xs)
            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(Design.Palette.ink)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 32)
    }
}
