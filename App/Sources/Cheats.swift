import Foundation

/// One `[Name]` block of a Gateway cheat file.
///
/// The core assembles exactly these blocks from `<user>/cheats/<title id>.txt` when a
/// game loads, and a block is applied only while it carries the `*citra_enabled` line
/// (`src/core/cheats/gateway_cheat.cpp`). Nothing here invents a format: the parser
/// mirrors the core's own line rules, and turning a cheat on or off only inserts or
/// removes that one line, leaving every other byte of the file as it was.
struct CheatEntry: Identifiable, Equatable {
    /// Position among the blocks the core would load, which is what a toggle edits.
    let id: Int
    let name: String
    /// The `*` note lines the core keeps alongside a cheat.
    let notes: [String]
    let codeLines: Int
    var isEnabled: Bool
}

/// A title's cheat file: what is in it, and the two edits this app makes to it.
struct CheatDocument {
    /// The exact line the core treats as "this block is on". It is compared with
    /// `==` after trimming spaces, so it must be written byte for byte.
    static let marker = "*citra_enabled"

    let url: URL
    private(set) var lines: [String]

    init(url: URL, text: String) {
        self.url = url
        var split = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        // A trailing newline is how the file ends, not an extra empty block.
        if split.last == "" {
            split.removeLast()
        }
        self.lines = split
    }

    // MARK: - Where the core looks

    /// `<user>/cheats/`; the user directory is Documents/Azahar in this app, so the
    /// core is already pointed at the folder these files belong in.
    static func directory(coreDirectory: URL) -> URL {
        coreDirectory.appendingPathComponent("cheats", isDirectory: true)
    }

    /// The core formats the id as `{:016X}` and appends `.txt`, so this name is not
    /// a convention of ours — it is the only name it will read.
    static func fileURL(titleID: String, coreDirectory: URL) -> URL {
        directory(coreDirectory: coreDirectory).appendingPathComponent("\(titleID).txt")
    }

    static func load(titleID: String, coreDirectory: URL) -> CheatDocument? {
        let target = fileURL(titleID: titleID, coreDirectory: coreDirectory)
        guard let data = try? Data(contentsOf: target),
              let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            return nil
        }
        return CheatDocument(url: target, text: text)
    }

    // MARK: - Reading

    private struct Block {
        var start: Int
        var name: String
        var notes: [String]
        var codeLines: Int
        var markerLine: Int?
    }

    /// The blocks in the order the core builds them: a `[Name]` line opens one, `*`
    /// lines are the marker or notes, anything else is code, and a block with no code
    /// is dropped — the core never loads one, so listing it would be a lie.
    private var blocks: [Block] {
        var finished: [Block] = []
        var current: Block?

        func closeCurrent() {
            if let block = current, block.codeLines > 0 {
                finished.append(block)
            }
            current = nil
        }

        for (index, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.count >= 2, line.hasPrefix("[") {
                closeCurrent()
                current = Block(start: index,
                                name: String(line.dropFirst().dropLast()),
                                notes: [],
                                codeLines: 0,
                                markerLine: nil)
            } else if !line.isEmpty, line.hasPrefix("*") {
                guard current != nil else { continue }
                if line == CheatDocument.marker {
                    current?.markerLine = index
                } else {
                    current?.notes.append(String(line.dropFirst()))
                }
            } else if !line.isEmpty {
                current?.codeLines += 1
            }
        }
        closeCurrent()
        return finished
    }

    var entries: [CheatEntry] {
        blocks.enumerated().map { index, block in
            CheatEntry(id: index,
                       name: block.name,
                       notes: block.notes,
                       codeLines: block.codeLines,
                       isEnabled: block.markerLine != nil)
        }
    }

    var enabledCount: Int {
        entries.filter { $0.isEnabled }.count
    }

    // MARK: - Writing

    /// Adds or removes the marker line for one block. Everything else stays put,
    /// including the notes and the codes.
    mutating func setEnabled(_ enabled: Bool, at id: Int) {
        let blocks = self.blocks
        guard blocks.indices.contains(id) else { return }
        let block = blocks[id]
        if enabled {
            guard block.markerLine == nil else { return }
            lines.insert(CheatDocument.marker, at: block.start + 1)
        } else {
            guard let marker = block.markerLine else { return }
            lines.remove(at: marker)
        }
    }

    func write() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true,
                                                attributes: nil)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// Copies a cheat file the user picked to this title's name. Nothing is kept in
    /// the app: the copied file is the state, and the core reads it at load.
    static func install(from source: URL, titleID: String, coreDirectory: URL) throws -> CheatDocument {
        let scoped = source.startAccessingSecurityScopedResource()
        defer {
            if scoped { source.stopAccessingSecurityScopedResource() }
        }
        let data = try Data(contentsOf: source)
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw CheatError.unreadableText
        }
        var document = CheatDocument(url: fileURL(titleID: titleID, coreDirectory: coreDirectory),
                                     text: text)
        try document.write()
        return document
    }

    enum CheatError: LocalizedError {
        case unreadableText

        var errorDescription: String? {
            switch self {
            case .unreadableText:
                return "That file is not readable text, so it cannot be a cheat file"
            }
        }
    }
}
