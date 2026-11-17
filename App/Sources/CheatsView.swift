import SwiftUI
import UniformTypeIdentifiers

/// The cheat manager on the Emulation page.
///
/// Cheats are not a setting: the core reads one file per title when it loads the
/// game, so this card is a view of those files and the sheet behind each row is the
/// only place anything is written.
struct CheatsCard: View {
    @EnvironmentObject private var library: GameLibrary
    @State private var rows: [Row] = []
    @State private var isLoaded = false
    @State private var openRow: Row?

    struct Row: Identifiable {
        let id: String
        let game: GameEntry
        let titleID: String?
        let document: CheatDocument?
    }

    var body: some View {
        SettingsCard("Cheats",
                     subtitle: "One file per title in Documents/Azahar/cheats, read when a game starts") {
            if !isLoaded {
                Text("Reading the library…")
                    .font(Design.Fonts.caption)
                    .foregroundColor(Design.Palette.secondaryInk)
            } else if rows.isEmpty {
                Text("No games in the library yet.")
                    .font(Design.Fonts.caption)
                    .foregroundColor(Design.Palette.secondaryInk)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        RowDivider()
                    }
                    Button(action: { openRow = row }) {
                        DesignRow(row.game.title, subtitle: subtitle(for: row)) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Design.Palette.secondaryInk)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle(scale: 0.99))
                    .pressHaptic()
                    .accessibilityHint(row.document == nil ? "No cheat file yet" : "Opens the cheats for this title")
                }
            }
        }
        .onAppear(perform: load)
        .onChange(of: library.games) { _ in load() }
        .sheet(item: $openRow) { row in
            CheatListSheet(row: row,
                           coreDirectory: library.coreDirectory,
                           onClose: {
                               openRow = nil
                               load()
                           })
        }
    }

    private func subtitle(for row: Row) -> String {
        if row.titleID == nil {
            return "The title id is not readable in this file, so no cheat file can be named for it"
        }
        guard let document = row.document else {
            return "No cheat file"
        }
        let total = document.entries.count
        guard total > 0 else {
            return "The file has no cheats the core would load"
        }
        return "\(total) \(total == 1 ? "cheat" : "cheats") · \(document.enabledCount) on"
    }

    /// Reading the header of every file is the one part of this that costs anything,
    /// so it happens off the main thread and only when the library or the page changes.
    private func load() {
        let games = library.games
        let coreDirectory = library.coreDirectory
        DispatchQueue.global(qos: .userInitiated).async {
            let rows = games.map { game -> Row in
                let titleID = game.url.flatMap { url in
                    ROMReader.titleID(url: url, fileExtension: url.pathExtension)
                }
                let document = titleID.flatMap {
                    CheatDocument.load(titleID: $0, coreDirectory: coreDirectory)
                }
                return Row(id: game.id, game: game, titleID: titleID, document: document)
            }
            DispatchQueue.main.async {
                self.rows = rows
                self.isLoaded = true
            }
        }
    }
}

/// One title's cheats: a switch per block, an import, and the file's path.
struct CheatListSheet: View {
    let row: CheatsCard.Row
    let coreDirectory: URL
    let onClose: () -> Void

    @State private var document: CheatDocument?
    @State private var entries: [CheatEntry] = []
    @State private var isImporting = false
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Space.l) {
                    column {
                        SettingsCard("This title", subtitle: fileLine) {
                            if let titleID = row.titleID {
                                infoRow("Title id", titleID)
                            }
                            infoRow("Status", statusLine)
                        }
                        .entrance(0)

                        if row.titleID == nil {
                            SettingsCard("No title id") {
                                Text("The 3DS header in this file does not give a title id, so there is no name to give a cheat file. A .zcci cannot be read for one either.")
                                    .font(Design.Fonts.caption)
                                    .foregroundColor(Design.Palette.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .entrance(1)
                        } else if entries.isEmpty {
                            SettingsCard("No cheats yet") {
                                Text("Import a cheat file and it is copied to the path above, which is where the core looks for this title.")
                                    .font(Design.Fonts.caption)
                                    .foregroundColor(Design.Palette.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                                importButton(title: "Import cheat file…")
                            }
                            .entrance(1)
                        } else {
                            SettingsCard("Cheats",
                                         subtitle: "Switches write the file. The core reads it when a game starts, so restart a running game.") {
                                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                    if index > 0 {
                                        RowDivider()
                                    }
                                    SettingRow(entry.name, subtitle: entrySubtitle(entry)) {
                                        SettingsToggle(isOn: entry.isEnabled) { value in
                                            setEnabled(value, entry: entry)
                                        }
                                    }
                                }
                                RowDivider()
                                importButton(title: "Replace cheat file…")
                            }
                            .entrance(1)
                        }

                        if let message = message {
                            Text(message)
                                .font(Design.Fonts.caption)
                                .foregroundColor(Design.Palette.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                                .entrance(2)
                        }

                        SettingsCard("How this works") {
                            Text("A cheat is a block of codes under a [name] line. It runs while the file carries the *citra_enabled line inside that block, which is what these switches add and remove. Nothing is stored in the app and no save is touched: if a cheat misbehaves, turn it off or delete the file.")
                                .font(Design.Fonts.caption)
                                .foregroundColor(Design.Palette.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .entrance(3)
                    }
                }
                .padding(.top, Design.Space.m)
                .padding(.bottom, Design.Space.xxl * 2)
            }
        }
        .background(Design.Palette.background.ignoresSafeArea())
        .onAppear(perform: reload)
        .fileImporter(isPresented: $isImporting,
                      allowedContentTypes: [.plainText],
                      allowsMultipleSelection: false) { result in
            importFile(result)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Design.Space.m) {
            VStack(alignment: .leading, spacing: Design.Space.xxs) {
                Text(row.game.title)
                    .font(Design.Fonts.title)
                    .foregroundColor(Design.Palette.ink)
                Text("Cheats")
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

    private var fileLine: String {
        guard let titleID = row.titleID else {
            return "Documents/Azahar/cheats"
        }
        return "Documents/Azahar/cheats/\(titleID).txt"
    }

    private var statusLine: String {
        guard row.titleID != nil else { return "cannot be matched to a file" }
        guard let document = document else { return "no cheat file" }
        return "\(document.entries.count) cheats, \(document.enabledCount) on"
    }

    private func entrySubtitle(_ entry: CheatEntry) -> String {
        let count = "\(entry.codeLines) \(entry.codeLines == 1 ? "line" : "lines")"
        if let note = entry.notes.first, !note.isEmpty {
            return "\(count) · \(note)"
        }
        return count
    }

    private func importButton(title: String) -> some View {
        Button(action: { isImporting = true }) {
            Text(title)
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

    private func reload() {
        guard let titleID = row.titleID else { return }
        document = CheatDocument.load(titleID: titleID, coreDirectory: coreDirectory)
        entries = document?.entries ?? []
    }

    private func setEnabled(_ enabled: Bool, entry: CheatEntry) {
        guard var document = document else { return }
        document.setEnabled(enabled, at: entry.id)
        do {
            try document.write()
            self.document = document
            entries = document.entries
            message = enabled ? "“\(entry.name)” on" : "“\(entry.name)” off"
        } catch {
            message = "Could not write the cheat file: \(error.localizedDescription)"
        }
    }

    private func importFile(_ result: Result<[URL], Error>) {
        guard let titleID = row.titleID else { return }
        switch result {
        case .failure(let error):
            message = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let installed = try CheatDocument.install(from: url,
                                                          titleID: titleID,
                                                          coreDirectory: coreDirectory)
                document = installed
                entries = installed.entries
                message = "Imported \(installed.entries.count) cheats"
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Space.xs) {
            Text(label)
                .font(Design.Fonts.caption)
                .foregroundColor(Design.Palette.secondaryInk)
            Spacer(minLength: Design.Space.xs)
            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(Design.Palette.ink)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 32)
    }

    private func column<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, Design.Space.sideMargin)
    }
}
