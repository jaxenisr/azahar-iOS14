import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: GameLibrary
    @State private var isImporting = false
    @State private var selected: GameEntry?

    private let columns = [
        GridItem(.adaptive(minimum: 156, maximum: 208), spacing: 20)
    ]

    var body: some View {
        ZStack {
            backdrop
            VStack(spacing: 0) {
                header
                content
            }
        }
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

    private var backdrop: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let icon = library.games.first?.icon {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 90)
                    .opacity(0.4)
                    .ignoresSafeArea()
            }
            BlurBackdrop().ignoresSafeArea()
        }
        .clipped()
    }

    private var header: some View {
        ScreenHeader(title: "Games",
                     subtitle: library.games.isEmpty
                        ? "No titles yet"
                        : "\(library.games.count) title\(library.games.count == 1 ? "" : "s")") {
            Button(action: { isImporting = true }) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Theme.primaryInk)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.chipFill))
                    .contentShape(Circle())
            }
            .buttonStyle(CardButtonStyle(scale: 0.94))
            .accessibilityLabel("Import a game")
        }
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var content: some View {
        if library.games.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(library.games) { game in
                        GameTile(game: game) { selected = game }
                    }
                }
                .padding(.horizontal, Theme.sideMargin)
                .padding(.bottom, Theme.bottomClearance)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(.white.opacity(0.35))
            Text("Import a .3ds, .cci or .zcci file")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
            Text("Files are copied into the app's Documents/ROMs folder.\n3DS system files go in Documents/Azahar.")
                .font(Theme.detail)
                .multilineTextAlignment(.center)
                .foregroundColor(Theme.tertiaryInk)
                .padding(.horizontal, 40)
            Spacer()
            Spacer()
        }
    }
}

struct GameTile: View {
    let game: GameEntry
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .fill(Theme.cardFill)
                    if let icon = game.icon {
                        Image(uiImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .padding(12)
                    } else {
                        Image(systemName: "gamecontroller")
                            .font(.system(size: 30, weight: .light))
                            .foregroundColor(.white.opacity(0.22))
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .stroke(Theme.cardStroke, lineWidth: 1)
                        .allowsHitTesting(false)
                )
                .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))

                Text(game.title)
                    .font(Theme.rowTitle)
                    .foregroundColor(Color.white.opacity(0.92))
                    .lineLimit(1)
                Text(game.subtitle)
                    .font(Theme.detail)
                    .foregroundColor(Theme.tertiaryInk)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(CardButtonStyle(scale: 0.97))
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
            Theme.backgroundSpotlight.ignoresSafeArea()
            ScrollView {
                VStack(spacing: Theme.cardSpacing) {
                    hero
                    playButton

                    SettingsCard("This title") {
                        SettingRow("Resolution scale", subtitle: gameOverride.resolutionScale == nil ? "Following the global value" : "Overridden for this title") {
                            MenuChip(title: gameOverride.resolutionScale.map { "\($0)x" } ?? "Global") {
                                Button("Use global") { update { $0.resolutionScale = nil } }
                                ForEach(1...4, id: \.self) { scale in
                                    Button("\(scale)x") { update { $0.resolutionScale = scale } }
                                }
                            }
                        }
                        SettingRow("Screen layout", subtitle: gameOverride.layout == nil ? "Following the global value" : "Overridden for this title") {
                            MenuChip(title: gameOverride.layout?.title ?? "Global") {
                                Button("Use global") { update { $0.layout = nil } }
                                ForEach(PlaybackLayout.allCases) { layout in
                                    Button(layout.title) { update { $0.layout = layout } }
                                }
                            }
                        }
                        SettingRow("Emulation speed", subtitle: gameOverride.speed == nil ? "Following the global value" : "Overridden for this title") {
                            MenuChip(title: gameOverride.speed?.title ?? "Global") {
                                Button("Use global") { update { $0.speed = nil } }
                                ForEach(PlaybackSpeed.allCases) { speed in
                                    Button(speed.title) { update { $0.speed = speed } }
                                }
                            }
                        }
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
                                    .font(Theme.chipFont)
                                    .foregroundColor(.white.opacity(0.75))
                                    .padding(.horizontal, 14)
                                    .chipSurface()
                            }
                            .buttonStyle(CardButtonStyle(scale: 0.96))
                        }
                    }

                    SettingsCard("Save state") {
                        HStack {
                            Text(PlaybackSession.stateDescription(for: game, coreDirectory: library.coreDirectory))
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(.white.opacity(0.85))
                            Spacer()
                        }
                        Text("One slot per title. Save and load it from the HUD while the game is running.")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.42))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SettingsCard("System files") {
                        ForEach(library.coreFileStatus()) { status in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: status.present ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(status.present ? Color.green.opacity(0.85) : Color.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(status.id)
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.88))
                                    Text(status.present ? status.note : "missing · \(status.note)")
                                        .font(.system(size: 11))
                                        .foregroundColor(status.present ? .white.opacity(0.42) : .orange.opacity(0.9))
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        Text("A decrypted dump boots with nothing else. Encrypted content needs sysdata/aes_keys.txt, and seeded titles need sysdata/seeddb.bin. Mii data and system saves live under nand/, which the core creates itself.")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.42))
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
                            .font(Theme.rowTitle)
                            .foregroundColor(.red.opacity(0.9))
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(CardButtonStyle(scale: 0.98))
                    .padding(.bottom, 60)
                }
                .padding(.horizontal, Theme.sideMargin)
                .padding(.top, 24)
            }
        }
        .fullScreenCover(item: $session) { session in
            PlaybackScreen(session: session)
        }
    }

    private var hero: some View {
        VStack(spacing: 10) {
            if let icon = game.icon {
                Image(uiImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 116, height: 116)
                    .cornerRadius(Theme.cardRadius)
                    .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
            }
            Text(game.title)
                .font(.system(size: 24, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
            Text(game.subtitle)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }

    private var playButton: some View {
        Button(action: {
            session = PlaybackSession(game: game,
                                      coreDirectory: library.coreDirectory,
                                      settings: effective)
        }) {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                Text("Play")
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(Theme.chipInk)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Capsule().fill(Color.white.opacity(0.92)))
            .contentShape(Capsule())
        }
        .buttonStyle(CardButtonStyle(scale: 0.995, pressedOpacity: 0.85))
    }

    private func update(_ body: (inout SettingsStore.GameOverride) -> Void) {
        var override = gameOverride
        body(&override)
        store.setOverride(override, for: game.id)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.42))
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.8))
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
            HStack(spacing: 6) {
                Text(title)
                    .font(Theme.chipFont)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundColor(Theme.chipText)
            .padding(.horizontal, 12)
            .chipSurface()
        }
    }
}

struct BlurBackdrop: UIViewRepresentable {
    var style: UIBlurEffect.Style = .systemUltraThinMaterialDark

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
