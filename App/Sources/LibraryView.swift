import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: GameLibrary
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var isImporting = false
    @State private var selected: GameEntry?

    /// Three across in regular width, two in a narrow split. The cell is the same
    /// object in both; only how many fit changes.
    private var columns: [GridItem] {
        let count = sizeClass == .compact ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: Design.Space.l, alignment: .top),
                     count: count)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .background(Design.Palette.background.ignoresSafeArea())
        .sheet(isPresented: $isImporting) {
            DocumentPicker { urls in
                library.importFiles(urls)
            }
        }
        .sheet(item: $selected) { game in
            GameDetailView(game: game)
                .environmentObject(library)
        }
        .alert(isPresented: Binding(get: { library.message != nil },
                                    set: { if !$0 { library.message = nil } })) {
            Alert(title: Text("Import problem"),
                  message: Text(library.message ?? ""),
                  dismissButton: .default(Text("OK")))
        }
    }

    private var header: some View {
        ScreenHeader(title: "Games",
                     subtitle: library.games.isEmpty
                        ? "No titles yet"
                        : "\(library.games.count) title\(library.games.count == 1 ? "" : "s")") {
            CircleButton(symbol: "plus", label: "Import a game") {
                isImporting = true
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if library.games.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: Design.Space.xl) {
                    ForEach(library.games) { game in
                        CoverCell(artwork: game.icon,
                                  name: game.title,
                                  meta: game.subtitle,
                                  aspect: 1,
                                  onOpen: { selected = game },
                                  onMenu: nil)
                    }
                }
                .padding(.horizontal, Design.Space.sideMargin)
                .padding(.top, Design.Space.s)
                .padding(.bottom, Design.Space.xxl * 3)
            }
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
}

struct GameDetailView: View {
    let game: GameEntry
    @EnvironmentObject private var library: GameLibrary
    @ObservedObject private var store = SettingsStore.shared
    @Environment(\.presentationMode) private var presentationMode
    @State private var session: PlaybackSession?

    private var gameOverride: SettingsStore.GameOverride { store.override(for: game.id) }
    private var effective: EmulationSettings { store.settings(for: game.id) }

    var body: some View {
        ZStack {
            Design.Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: Design.Space.l) {
                    hero
                    playButton

                    column {
                        SettingsCard("This title") {
                            SettingRow("Resolution scale", subtitle: gameOverride.resolutionScale == nil ? "Following the global value" : "Overridden for this title") {
                                MenuChip(title: gameOverride.resolutionScale.map { "\($0)x" } ?? "Global") {
                                    Button("Use global") { update { $0.resolutionScale = nil } }
                                    ForEach(1...4, id: \.self) { scale in
                                        Button("\(scale)x") { update { $0.resolutionScale = scale } }
                                    }
                                }
                            }
                            RowDivider()
                            SettingRow("Screen layout", subtitle: gameOverride.layout == nil ? "Following the global value" : "Overridden for this title") {
                                MenuChip(title: gameOverride.layout?.title ?? "Global") {
                                    Button("Use global") { update { $0.layout = nil } }
                                    ForEach(PlaybackLayout.allCases) { layout in
                                        Button(layout.title) { update { $0.layout = layout } }
                                    }
                                }
                            }
                            RowDivider()
                            SettingRow("Emulation speed", subtitle: gameOverride.speed == nil ? "Following the global value" : "Overridden for this title") {
                                MenuChip(title: gameOverride.speed?.title ?? "Global") {
                                    Button("Use global") { update { $0.speed = nil } }
                                    ForEach(PlaybackSpeed.allCases) { speed in
                                        Button(speed.title) { update { $0.speed = speed } }
                                    }
                                }
                            }
                            RowDivider()
                            SettingRow("3DS CPU clock", subtitle: gameOverride.cpuClockPercent == nil ? "Following the global value" : "Overridden for this title") {
                                MenuChip(title: gameOverride.cpuClockPercent.map { "\($0)%" } ?? "Global") {
                                    Button("Use global") { update { $0.cpuClockPercent = nil } }
                                    ForEach(EmulationSettings.cpuClockChoices, id: \.self) { percent in
                                        Button("\(percent)%") { update { $0.cpuClockPercent = percent } }
                                    }
                                }
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
                            }
                        }

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

                        SettingsCard("System files") {
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
                            }
                            Text("A decrypted dump boots with nothing else. Encrypted content needs sysdata/aes_keys.txt, and seeded titles need sysdata/seeddb.bin. Mii data and system saves live under nand/, which the core creates itself.")
                                .font(Design.Fonts.caption)
                                .foregroundColor(Design.Palette.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        SettingsCard("File") {
                            infoRow("Name", game.url.lastPathComponent)
                            infoRow("Core", library.coreDescription)
                            infoRow("Core check", library.coreStatus)
                        }

                        Button(action: {
                            library.remove(game)
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            Text("Remove from library")
                                .font(Design.Fonts.rowTitle)
                                .foregroundColor(Color.red.opacity(0.9))
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle(scale: 0.98))
                    }
                }
                .padding(.top, Design.Space.l)
                .padding(.bottom, Design.Space.xxl * 2)
            }
        }
        .fullScreenCover(item: $session) { session in
            PlaybackScreen(session: session)
        }
    }

    private var hero: some View {
        VStack(spacing: Design.Space.s) {
            if let icon = game.icon {
                Image(uiImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 116, height: 116)
                    .clipShape(RoundedRectangle(cornerRadius: Design.Radius.cover, style: .continuous))
                    .designShadow(Design.Elevation.card)
            }
            Text(game.title)
                .font(.system(size: 24, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundColor(Design.Palette.ink)
                .padding(.horizontal, Design.Space.s)
            Text(game.subtitle)
                .font(Design.Fonts.caption)
                .foregroundColor(Design.Palette.secondaryInk)
        }
        .frame(maxWidth: .infinity)
    }

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
        .padding(.horizontal, Design.Space.sideMargin)
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
}

struct MenuChip<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        Menu {
            content
        } label: {
            HStack(spacing: Design.Space.xxs) {
                Text(title)
                    .font(Design.Fonts.caption.weight(.semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundColor(Design.Palette.ink)
            .padding(.horizontal, Design.Space.s)
            .frame(height: 32)
            .background(Capsule().fill(Design.Palette.card))
            .overlay(Capsule().stroke(Design.Palette.hairline, lineWidth: 1))
            .contentShape(Capsule())
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
