import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: GameLibrary
    @State private var isImporting = false
    @State private var selected: GameEntry?

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 22)
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
            Color(red: 0.04, green: 0.05, blue: 0.07).ignoresSafeArea()
            if let icon = library.games.first?.icon {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 90)
                    .opacity(0.45)
                    .ignoresSafeArea()
            }
            BlurBackdrop().ignoresSafeArea()
        }
        .clipped()
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Library")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                Text(library.games.isEmpty
                     ? "No titles yet"
                     : "\(library.games.count) title\(library.games.count == 1 ? "" : "s")")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()
            Button(action: { isImporting = true }) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .accessibilityLabel("Import a game")
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private var content: some View {
        if library.games.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 22) {
                    ForEach(library.games) { game in
                        GameTile(game: game) { selected = game }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
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
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.45))
                .padding(.horizontal, 40)
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
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.07))
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
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

                Text(game.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)
                Text(game.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(1)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct GameDetailView: View {
    let game: GameEntry
    @EnvironmentObject private var library: GameLibrary
    @Environment(\.presentationMode) private var presentationMode
    @State private var session: PlaybackSession?
    @State private var resolutionScale = 1
    @State private var layout: PlaybackLayout = .largeScreen

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.07, blue: 0.09).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    if let icon = game.icon {
                        Image(uiImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 128, height: 128)
                            .cornerRadius(16)
                            .padding(.top, 28)
                    }
                    Text(game.title)
                        .font(.system(size: 22, weight: .bold))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                    Text(game.subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))

                    infoRow("File", game.url.lastPathComponent)
                    infoRow("Core", library.coreDescription)
                    infoRow("Core check", library.coreStatus)

                    Button(action: {
                        session = PlaybackSession(game: game,
                                                  coreDirectory: library.coreDirectory,
                                                  resolutionScale: resolutionScale,
                                                  layout: layout)
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                            Text("Play")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: 220)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.white.opacity(0.16)))
                    }
                    .padding(.top, 4)

                    resolutionPicker

                    layoutPicker

                    requirements

                    Button(action: {
                        library.remove(game)
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Text("Remove from library")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.red.opacity(0.9))
                            .padding(.top, 10)
                    }
                    .padding(.bottom, 32)
                }
            }
        }
        .fullScreenCover(item: $session) { session in
            PlaybackScreen(session: session)
        }
    }

    private var resolutionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Resolution scale")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.45))
                Spacer()
                Text("\(resolutionScale)x · applied when playback starts")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
            }
            HStack(spacing: 8) {
                ForEach(1...4, id: \.self) { scale in
                    Button(action: { resolutionScale = scale }) {
                        Text("\(scale)x")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(resolutionScale == scale ? .black : .white.opacity(0.8))
                            .frame(width: 54, height: 30)
                            .background(
                                Capsule().fill(resolutionScale == scale
                                               ? Color.white.opacity(0.85)
                                               : Color.white.opacity(0.12))
                            )
                    }
                }
                Spacer()
            }
        }
        .padding(.horizontal, 28)
    }

    private var layoutPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Screen layout")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.45))
                Spacer()
                Text("applied when playback starts")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
            }
            HStack(spacing: 8) {
                ForEach(PlaybackLayout.allCases) { option in
                    Button(action: { layout = option }) {
                        Text(option.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(layout == option ? .black : .white.opacity(0.8))
                            .padding(.horizontal, 16)
                            .frame(height: 30)
                            .background(
                                Capsule().fill(layout == option
                                               ? Color.white.opacity(0.85)
                                               : Color.white.opacity(0.12))
                            )
                    }
                }
                Spacer()
            }
        }
        .padding(.horizontal, 28)
    }

    private var requirements: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Beyond the ROM")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.45))
                Spacer()
            }

            ForEach(library.coreFileStatus()) { status in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: status.present ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12))
                        .foregroundColor(status.present ? Color.green.opacity(0.8) : Color.white.opacity(0.3))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(status.id)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))
                        Text(status.note)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.45))
                    }
                    Spacer(minLength: 0)
                }
            }

            Text("Azahar keeps its own user directory under Documents/Azahar. A decrypted dump boots with nothing else in it. Encrypted content needs sysdata/aes_keys.txt and, for seeded titles, sysdata/seeddb.bin; Mii data and system saves live under nand/, which the core creates itself. Whether this file is encrypted is decided by the core when it loads it: an encrypted dump is refused with \"This ROM is encrypted and must be decrypted before use with Azahar.\", and any missing archive is named on the playback screen.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 28)
        .padding(.top, 6)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.45))
                .frame(width: 84, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
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
