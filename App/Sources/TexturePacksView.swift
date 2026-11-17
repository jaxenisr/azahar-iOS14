import SwiftUI

/// The texture-pack inventory on the Emulation page.
///
/// A pack is a folder, not a setting, so this card is a view of those folders: the
/// core only scans one when a game starts, and the switches that turn loading and
/// dumping on sit in the Graphics card with the rest of the graphics options.
struct TexturePacksCard: View {
    @EnvironmentObject private var library: GameLibrary
    @State private var rows: [Row] = []
    @State private var isLoaded = false
    @State private var openRow: Row?

    struct Row: Identifiable {
        let id: String
        let game: GameEntry
        let titleID: String?
        let pack: TexturePack?
    }

    var body: some View {
        SettingsCard("Texture packs",
                     subtitle: "A folder per title in Documents/Azahar/load/textures, scanned when a game starts") {
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
                    .accessibilityHint(row.pack == nil ? "No texture pack yet" : "Opens the texture pack for this title")
                }
            }
        }
        .onAppear(perform: load)
        .onChange(of: library.games) { _ in load() }
        .sheet(item: $openRow) { row in
            TexturePackSheet(row: row,
                             coreDirectory: library.coreDirectory) {
                openRow = nil
            }
        }
    }

    private func subtitle(for row: Row) -> String {
        if row.titleID == nil {
            return "The title id is not readable in this file, so no pack folder can be named for it"
        }
        guard let pack = row.pack else {
            return "No pack"
        }
        var text = "\(pack.textureCount) \(pack.textureCount == 1 ? "texture" : "textures") · \(pack.sizeDescription)"
        if let author = pack.info?.author, !author.isEmpty {
            text += " · \(author)"
        }
        return text
    }

    /// Reading a pack means walking its folder, so it happens off the main thread
    /// and only when the library or the page changes.
    private func load() {
        let games = library.games
        let coreDirectory = library.coreDirectory
        DispatchQueue.global(qos: .userInitiated).async {
            let rows = games.map { game -> Row in
                let titleID = game.url.flatMap { url in
                    ROMReader.titleID(url: url, fileExtension: url.pathExtension)
                }
                let pack = titleID.flatMap {
                    TexturePack.load(titleID: $0, coreDirectory: coreDirectory)
                }
                return Row(id: game.id, game: game, titleID: titleID, pack: pack)
            }
            DispatchQueue.main.async {
                self.rows = rows
                self.isLoaded = true
            }
        }
    }
}

/// One title's pack: what is in the folder, what its `pack.json` says, and where
/// the core loads and dumps from.
struct TexturePackSheet: View {
    let row: TexturePacksCard.Row
    let coreDirectory: URL
    let onClose: () -> Void

    @State private var dumpedCount = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Space.l) {
                    column {
                        SettingsCard("This title", subtitle: folderLine) {
                            if let titleID = row.titleID {
                                infoRow("Title id", titleID)
                            }
                            infoRow("Pack", statusLine)
                            infoRow("Dumped", dumpedLine)
                        }
                        .entrance(0)

                        if row.titleID == nil {
                            SettingsCard("No title id") {
                                Text("The 3DS header in this file does not give a title id, so there is no folder name the core would ever scan for this title. A .zcci cannot be read for one either.")
                                    .font(Design.Fonts.caption)
                                    .foregroundColor(Design.Palette.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .entrance(1)
                        } else if let pack = row.pack {
                            SettingsCard("The pack",
                                         subtitle: "What the folder holds, counted the way the core counts it") {
                                infoRow("Textures", "\(pack.textureCount) · \(pack.sizeDescription)")
                                if let info = pack.info {
                                    RowDivider()
                                    infoRow("pack.json", "read: options and texture map")
                                    if let author = info.author, !author.isEmpty {
                                        RowDivider()
                                        infoRow("Author", author)
                                    }
                                    if let version = info.version, !version.isEmpty {
                                        RowDivider()
                                        infoRow("Version", version)
                                    }
                                    if let summary = info.summary, !summary.isEmpty {
                                        RowDivider()
                                        infoRow("Description", summary)
                                    }
                                } else {
                                    RowDivider()
                                    infoRow("pack.json", "absent: legacy hash, mipmaps skipped")
                                }
                            }
                            .entrance(1)
                        } else {
                            SettingsCard("No pack yet") {
                                Text("Make a folder named for the title id above inside Documents/Azahar/load/textures, put the pack's .png files in it (a pack.json is optional), then turn on Texture packs under Graphics. The core scans the folder when the game starts.")
                                    .font(Design.Fonts.caption)
                                    .foregroundColor(Design.Palette.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .entrance(1)
                        }

                        SettingsCard("How this works") {
                            Text("The core replaces a texture only when it finds a file whose name carries that texture's hash, and it looks in load/textures/<title id> only while Texture packs is on. Files are read whole, so a large pack on a 3 GB device is the real cost of this, not the loading. Dumps land in dump/textures/<title id>, a separate folder that the core writes when Dump textures under Graphics is on: they are the raw material for making a pack, not a pack. Restart a running game after changing either switch.")
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
        .onAppear(perform: countDumps)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Design.Space.m) {
            VStack(alignment: .leading, spacing: Design.Space.xxs) {
                Text(row.game.title)
                    .font(Design.Fonts.title)
                    .foregroundColor(Design.Palette.ink)
                Text("Texture pack")
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

    private var folderLine: String {
        guard let titleID = row.titleID else {
            return "Documents/Azahar/load/textures"
        }
        return "Documents/Azahar/load/textures/\(titleID)"
    }

    private var statusLine: String {
        guard row.titleID != nil else { return "cannot be matched to a folder" }
        guard let pack = row.pack else { return "no folder with textures in it" }
        return "\(pack.textureCount) textures, \(pack.sizeDescription)"
    }

    private var dumpedLine: String {
        guard row.titleID != nil else { return "—" }
        guard dumpedCount > 0 else { return "nothing dumped" }
        return "\(dumpedCount) \(dumpedCount == 1 ? "texture" : "textures") in dump/textures"
    }

    private func countDumps() {
        guard let titleID = row.titleID else { return }
        let coreDirectory = self.coreDirectory
        DispatchQueue.global(qos: .userInitiated).async {
            let count = TexturePack.dumpedCount(titleID: titleID, coreDirectory: coreDirectory)
            DispatchQueue.main.async {
                self.dumpedCount = count
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
                .fixedSize(horizontal: false, vertical: true)
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
