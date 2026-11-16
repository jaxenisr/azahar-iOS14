import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// What the library is showing. One system, so the switch has two sides rather
/// than a picker: titles, or the system files the core reads.
enum LibraryMode: String, CaseIterable, Identifiable {
    case games
    case systemFiles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .games: return "Game"
        case .systemFiles: return "System File"
        }
    }
}

/// One letter of the library, so `ForEach` has something to identify.
private struct LibrarySection: Identifiable {
    let letter: String
    let games: [GameEntry]

    var id: String { letter }
}

struct LibraryView: View {
    @EnvironmentObject private var library: GameLibrary
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var isImporting = false
    @State private var selected: GameEntry?
    @State private var menuGame: GameEntry?
    @State private var mode: LibraryMode = .games
    /// The cover and the pane's hero share this namespace.
    @Namespace private var hero

    private var isCompact: Bool { sizeClass == .compact }

    /// Three across in regular width, two in a narrow split. The cell is the same
    /// object in both; only how many fit changes.
    private var columns: [GridItem] {
        let count = isCompact ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: Design.Space.l, alignment: .top),
                     count: count)
    }

    /// Titles bucketed by their first letter, in alphabetical order, with anything
    /// that does not start with a letter under `#`. This is what makes a large
    /// library scannable.
    private var sections: [LibrarySection] {
        var buckets: [String: [GameEntry]] = [:]
        for game in library.games {
            let first = game.title.first.map { String($0).uppercased() } ?? "#"
            let key = first.rangeOfCharacter(from: .letters) == nil ? "#" : first
            buckets[key, default: []].append(game)
        }
        return buckets.keys.sorted().map { key in
            LibrarySection(letter: key,
                           games: (buckets[key] ?? []).sorted {
                               $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                           })
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .trailing) {
                VStack(spacing: 0) {
                    header
                    page
                }

                if let game = selected {
                    Color.black.opacity(0.22)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { closeDetail() }
                        .transition(.opacity)
                        .animation(Design.Motion.backdrop)

                    detailPane(for: game, available: geometry.size.width)
                        .transition(.move(edge: .trailing))
                        .animation(Design.Motion.panel)
                }
            }
        }
        .background(Design.Palette.background.ignoresSafeArea())
        .sheet(isPresented: $isImporting) {
            DocumentPicker { urls in
                library.importFiles(urls)
            }
        }
        .actionSheet(isPresented: Binding(get: { menuGame != nil },
                                          set: { if !$0 { menuGame = nil } })) {
            actionSheet
        }
        .alert(isPresented: Binding(get: { library.message != nil },
                                    set: { if !$0 { library.message = nil } })) {
            Alert(title: Text("Import problem"),
                  message: Text(library.message ?? ""),
                  dismissButton: .default(Text("OK")))
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Design.Space.s) {
            HStack(alignment: .top, spacing: Design.Space.m) {
                VStack(alignment: .leading, spacing: Design.Space.xxs) {
                    Text(mode == .games ? "Games" : "System Files")
                        .font(Design.Fonts.title)
                        .foregroundColor(Design.Palette.ink)
                    Text(mode == .games ? "Nintendo 3DS" : "Documents/Azahar")
                        .font(Design.Fonts.rowSubtitle)
                        .foregroundColor(Design.Palette.secondaryInk)
                    Text(countLine)
                        .font(Design.Fonts.caption)
                        .foregroundColor(Design.Palette.secondaryInk)
                }
                Spacer(minLength: Design.Space.xs)
                HStack(spacing: Design.Space.xs) {
                    CircleButton(symbol: "plus", label: "Import a game") {
                        isImporting = true
                    }
                    moreButton
                    systemsButton
                }
            }

            ChipRow(options: LibraryMode.allCases.map { $0.title },
                    selection: LibraryMode.allCases.firstIndex(of: mode) ?? 0) { index in
                mode = LibraryMode.allCases[index]
            }
        }
        .padding(.horizontal, Design.Space.sideMargin)
        .padding(.top, Design.Space.l)
        .padding(.bottom, Design.Space.s)
    }

    private var countLine: String {
        switch mode {
        case .games:
            let count = library.games.count
            return count == 0 ? "No titles yet" : "\(count) title\(count == 1 ? "" : "s")"
        case .systemFiles:
            return "Read by the core at boot"
        }
    }

    /// Two real actions and no invented ones: rescanning the folder matters when a
    /// file was added over Files.app while the app was open.
    private var moreButton: some View {
        Menu {
            Button(action: { library.reload() }) {
                Label("Rescan library", systemImage: "arrow.clockwise")
            }
            Button(action: { isImporting = true }) {
                Label("Import a game", systemImage: "plus")
            }
        } label: {
            circleLabel("ellipsis")
        }
    }

    /// The systems list. This app has exactly one system, and the menu says so
    /// rather than pretending there is a picker.
    private var systemsButton: some View {
        Menu {
            Text("Nintendo 3DS — the only system this app runs")
        } label: {
            circleLabel("globe")
        }
    }

    private func circleLabel(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(Design.Palette.ink)
            .frame(width: 44, height: 44)
            .background(Circle().fill(Design.Palette.card))
            .overlay(Circle().stroke(Design.Palette.hairline, lineWidth: 1))
            .designShadow(Design.Elevation.cover)
            .contentShape(Circle())
    }

    // MARK: - Pages

    @ViewBuilder
    private var page: some View {
        switch mode {
        case .games:
            if library.games.isEmpty {
                emptyState
            } else {
                gameGrid
            }
        case .systemFiles:
            systemFileList
        }
    }

    private var gameGrid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Design.Space.xl) {
                ForEach(sections.indices, id: \.self) { index in
                    sectionView(sections[index], index: index)
                }
            }
            .padding(.horizontal, Design.Space.sideMargin)
            .padding(.top, Design.Space.s)
            .padding(.bottom, Design.Space.xxl * 3)
        }
    }

    private func sectionView(_ section: LibrarySection, index: Int) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.s) {
            Text(section.letter)
                .font(Design.Fonts.section)
                .foregroundColor(Design.Palette.ink)
            LazyVGrid(columns: columns, alignment: .leading, spacing: Design.Space.l) {
                ForEach(section.games) { game in
                    CoverCell(artwork: game.icon,
                              name: game.title,
                              meta: game.subtitle,
                              aspect: 1,
                              heroNamespace: hero,
                              heroID: game.id,
                              heroSource: selected?.id != game.id,
                              onOpen: { openDetail(game) },
                              onMenu: { menuGame = game })
                }
            }
        }
        .entrance(index)
    }

    private var systemFileList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Space.l) {
                DesignCard("In Documents/Azahar") {
                    ForEach(library.coreFileStatus()) { status in
                        HStack(alignment: .top, spacing: Design.Space.s) {
                            Image(systemName: status.present ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(status.present ? Design.Palette.positive : Color.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(status.id)
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundColor(Design.Palette.ink)
                                Text(status.present ? status.note : "missing · \(status.note)")
                                    .font(Design.Fonts.caption)
                                    .foregroundColor(status.present ? Design.Palette.secondaryInk : Color.orange)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .entrance(0)

                Text("A decrypted dump boots with nothing else. Encrypted content needs sysdata/aes_keys.txt, and seeded titles need sysdata/seeddb.bin. Mii data and system saves live under nand/, which the core creates itself.")
                    .font(Design.Fonts.caption)
                    .foregroundColor(Design.Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Design.Space.sideMargin)
                    .entrance(1)
            }
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, Design.Space.sideMargin)
            .padding(.top, Design.Space.s)
            .padding(.bottom, Design.Space.xxl * 3)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Design.Space.m) {
            Spacer()
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(Design.Palette.secondaryInk)
            Text("Import a .3ds, .cci or .zcci file")
                .font(Design.Fonts.rowTitle)
                .foregroundColor(Design.Palette.ink)
            Text("Files are copied into the app's Documents/ROMs folder.\n3DS system files go in Documents/Azahar.")
                .font(Design.Fonts.caption)
                .multilineTextAlignment(.center)
                .foregroundColor(Design.Palette.secondaryInk)
                .padding(.horizontal, 40)
            Spacer()
            Spacer()
        }
    }

    // MARK: - Detail

    /// Regular width: a pane over the right half, with the grid still visible. A
    /// narrow split has no room for that, so the pane is the whole width.
    private func detailPane(for game: GameEntry, available: CGFloat) -> some View {
        let width = isCompact ? available : min(max(available * 0.55, 420), 620)
        return GameDetailView(game: game,
                              onClose: { closeDetail() },
                              heroNamespace: hero)
            .frame(width: width)
            .background(Design.Palette.background)
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
                    .stroke(Design.Palette.hairline, lineWidth: 1)
                    .allowsHitTesting(false)
            )
            .designShadow(Design.Elevation.card)
            .padding(.trailing, isCompact ? 0 : Design.Space.xs)
            .padding(.vertical, isCompact ? 0 : Design.Space.xs)
            // Pulling the pane down closes it, the way a sheet does.
            .gesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        if value.translation.height > 120 { closeDetail() }
                    }
            )
    }

    private func openDetail(_ game: GameEntry) {
        withAnimation(Design.Motion.panel) {
            selected = game
        }
    }

    private func closeDetail() {
        withAnimation(Design.Motion.panel) {
            selected = nil
        }
    }

    // MARK: - Per-title menu

    private var actionSheet: ActionSheet {
        let game = menuGame
        return ActionSheet(title: Text(game?.title ?? ""),
                           buttons: [
                            .default(Text("Open")) {
                                if let game = game { openDetail(game) }
                            },
                            .destructive(Text("Remove from library")) {
                                if let game = game { library.remove(game) }
                            },
                            .cancel()
                           ])
    }
}

/// The title page: art, name, size, one Play button, and the settings this title
/// can override. Presented as a pane by the library, so its closing is the
/// caller's business rather than a modal presentation.
struct GameDetailView: View {
    let game: GameEntry
    var onClose: (() -> Void)? = nil
    /// The library's namespace, so the cover can grow into this hero.
    let heroNamespace: Namespace.ID

    @EnvironmentObject private var library: GameLibrary
    @ObservedObject private var store = SettingsStore.shared
    @Environment(\.presentationMode) private var presentationMode
    @State private var session: PlaybackSession?

    private var gameOverride: SettingsStore.GameOverride { store.override(for: game.id) }
    private var effective: EmulationSettings { store.settings(for: game.id) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Design.Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: Design.Space.l) {
                    hero
                    playButton

                    column {
                        SettingsCard("This title") {
                            MenuSettingRow(title: "Resolution scale",
                                           subtitle: overrideNote(gameOverride.resolutionScale == nil),
                                           options: (1...4).map {
                                               MenuSettingRow<Int>.Option(title: "\($0)x", value: $0)
                                           },
                                           selection: gameOverride.resolutionScale) { value in
                                update { $0.resolutionScale = value }
                            }
                            RowDivider()
                            MenuSettingRow(title: "Screen layout",
                                           subtitle: overrideNote(gameOverride.layout == nil),
                                           options: PlaybackLayout.allCases.map {
                                               MenuSettingRow<PlaybackLayout>.Option(title: $0.title, value: $0)
                                           },
                                           selection: gameOverride.layout) { value in
                                update { $0.layout = value }
                            }
                            RowDivider()
                            MenuSettingRow(title: "Emulation speed",
                                           subtitle: overrideNote(gameOverride.speed == nil),
                                           options: PlaybackSpeed.allCases.map {
                                               MenuSettingRow<PlaybackSpeed>.Option(title: $0.title, value: $0)
                                           },
                                           selection: gameOverride.speed) { value in
                                update { $0.speed = value }
                            }
                            RowDivider()
                            MenuSettingRow(title: "3DS CPU clock",
                                           subtitle: overrideNote(gameOverride.cpuClockPercent == nil),
                                           options: EmulationSettings.cpuClockChoices.map {
                                               MenuSettingRow<Int>.Option(title: "\($0)%", value: $0)
                                           },
                                           selection: gameOverride.cpuClockPercent) { value in
                                update { $0.cpuClockPercent = value }
                            }
                            RowDivider()
                            MenuSettingRow(title: "Region",
                                           subtitle: overrideNote(gameOverride.region == nil),
                                           options: PlaybackRegion.allCases.map {
                                               MenuSettingRow<PlaybackRegion>.Option(title: $0.title, value: $0)
                                           },
                                           selection: gameOverride.region) { value in
                                update { $0.region = value }
                            }

                            if store.hasOverride(for: game.id) {
                                Button(action: { store.clearOverride(for: game.id) }) {
                                    Text("Reset to global")
                                        .font(Design.Fonts.caption.weight(.semibold))
                                        .foregroundColor(Design.Palette.ink)
                                        .padding(.horizontal, Design.Space.m)
                                        .frame(height: 32)
                                        .background(Capsule().fill(Design.Palette.card))
                                        .overlay(Capsule().stroke(Design.Palette.hairline, lineWidth: 1))
                                        .contentShape(Capsule())
                                }
                                .buttonStyle(PressableStyle())
                                .pressHaptic()
                            }
                        }
                        .entrance(0)

                        SettingsCard("Save state") {
                            HStack {
                                Text(PlaybackSession.stateDescription(for: game, coreDirectory: library.coreDirectory))
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(Design.Palette.ink)
                                Spacer()
                            }
                            Text("One slot per title. Save and load it from the HUD while the game is running.")
                                .font(Design.Fonts.caption)
                                .foregroundColor(Design.Palette.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .entrance(1)

                        SettingsCard("File") {
                            infoRow("Name", game.url.lastPathComponent)
                            infoRow("Size", game.subtitle)
                            infoRow("Core", library.coreDescription)
                        }
                        .entrance(2)

                        Button(action: remove) {
                            Text("Remove from library")
                                .font(Design.Fonts.rowTitle)
                                .foregroundColor(Color.red.opacity(0.9))
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle(scale: 0.98))
                        .pressHaptic()
                        .entrance(3)
                    }
                }
                .padding(.top, Design.Space.xxl)
                .padding(.bottom, Design.Space.xxl * 2)
            }

            closeButton
        }
        .fullScreenCover(item: $session) { session in
            PlaybackScreen(session: session)
        }
    }

    private var closeButton: some View {
        CircleButton(symbol: "xmark", label: "Close") {
            close()
        }
        .padding(Design.Space.m)
    }

    /// The artwork the cover handed over, drawn at the pane's size under the same
    /// geometry id, so it grows rather than arriving twice.
    ///
    /// The text keeps a wide margin on both sides: the close button lives in this
    /// corner, and a long title without that room runs underneath it and becomes
    /// unreadable exactly where the two overlap. The margin is the button plus its
    /// padding, measured once here rather than guessed per title.
    private var hero: some View {
        VStack(spacing: Design.Space.s) {
            Group {
                if let icon = game.icon {
                    Image(uiImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 132, height: 132)
                        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.cover, style: .continuous))
                        .designShadow(Design.Elevation.card)
                        .matchedGeometryEffect(id: game.id, in: heroNamespace)
                }
            }

            Text(game.title)
                .font(.system(size: 24, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundColor(Design.Palette.ink)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, GameDetailView.titleInset)
            Text(game.subtitle)
                .font(Design.Fonts.caption)
                .foregroundColor(Design.Palette.secondaryInk)
                .padding(.horizontal, GameDetailView.titleInset)
        }
        .frame(maxWidth: .infinity)
        .entrance(0)
    }

    /// A 44 pt close button with its 12 pt padding, plus a little air.
    private static let titleInset: CGFloat = 64

    private var playButton: some View {
        Button(action: {
            session = PlaybackSession(game: game,
                                      coreDirectory: library.coreDirectory,
                                      settings: effective)
        }) {
            HStack(spacing: Design.Space.xs) {
                Image(systemName: "play.fill")
                Text("Play")
            }
            .font(Design.Fonts.rowTitle)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Capsule().fill(Design.Palette.accent))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.99))
        .pressHaptic()
        .padding(.horizontal, Design.Space.sideMargin)
    }

    /// What a menu row says on a title page when this title has not overridden it.
    /// The value column reads `Default` — one word for one idea, and the menu
    /// offers the same word as its first line, which is what puts the setting back
    /// to inheriting — so this line says only where that default comes from.
    private func overrideNote(_ isInherited: Bool) -> String {
        isInherited ? "Following the global value" : "Overridden for this title"
    }

    /// The same column the settings screens use: 720 pt cap, 20 pt margins.
    private func column<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, Design.Space.sideMargin)
    }

    private func update(_ body: (inout SettingsStore.GameOverride) -> Void) {
        var override = gameOverride
        body(&override)
        store.setOverride(override, for: game.id)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(Design.Fonts.caption.weight(.semibold))
                .foregroundColor(Design.Palette.secondaryInk)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(Design.Fonts.caption)
                .foregroundColor(Design.Palette.ink)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
    }

    private func remove() {
        library.remove(game)
        close()
    }


    private func close() {
        if let onClose = onClose {
            onClose()
        } else {
            presentationMode.wrappedValue.dismiss()
        }
    }
}

/// The app's only `UIVisualEffectView` wrapper. Floating panels are the one place
/// a blur is allowed; nothing else may stack a second one over it.
struct BlurBackdrop: UIViewRepresentable {
    var style: UIBlurEffect.Style = .systemMaterial

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ view: UIVisualEffectView, context: Context) {
        view.effect = UIBlurEffect(style: style)
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    var onPick: ([URL]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        var types: [UTType] = []
        for ext in GameLibrary.romExtensions {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        if types.isEmpty {
            types = [.data]
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: ([URL]) -> Void

        init(onPick: @escaping ([URL]) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}
