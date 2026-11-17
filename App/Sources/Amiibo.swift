import Foundation

/// One amiibo dump, and the folder this app keeps them in.
///
/// The 3DS's reader is a file here, not a radio. The core's NFC service takes a
/// tag from a path the frontend chooses, which is what the desktop frontend does
/// with a `.bin`, so the app's job is the file: it holds the dumps in
/// `Documents/Azahar/amiibo`, says what each one is, and hands one over while a
/// game is asking for it.
///
/// What the reader gets is this app's copy. The core writes an in-game change —
/// a saved level, a trained fighter — back into the file it was given, so the
/// user's own dump is only ever read.
struct AmiiboTag: Identifiable, Equatable {
    /// The file's name, which is also its identity: two dumps of the same
    /// figure are two files.
    let id: String
    let url: URL
    let byteCount: Int64
    let modified: Date?

    /// One NTAG215 dump is 0x21C bytes, plain or encrypted, and the core reads
    /// exactly that many. Anything else is refused, so the sheet says why before
    /// the reader has to.
    static let tagSize: Int64 = 0x21C

    var displayName: String {
        (id as NSString).deletingPathExtension
    }

    var isTagSized: Bool {
        byteCount == AmiiboTag.tagSize
    }

    var sizeDescription: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes]
        formatter.countStyle = .file
        var text = formatter.string(fromByteCount: byteCount)
        if let modified = modified {
            let stamp = DateFormatter()
            stamp.dateStyle = .medium
            stamp.timeStyle = .none
            text += " · " + stamp.string(from: modified)
        }
        return text
    }
}

/// What the core's NFC service is doing, in the four states its own predicates
/// describe.
enum AmiiboState: Int {
    /// No game, or a title with no NFC service.
    case unavailable = 0
    /// A game is running and has not asked for a tag.
    case waiting = 1
    /// The game is asking for a tag; the reader is empty.
    case scanning = 2
    /// A tag is loaded.
    case loaded = 3
}

/// The folder, the dumps in it, and the three calls into the reader.
enum AmiiboLibrary {
    /// This app's own folder. The core has no amiibo directory of its own — it
    /// opens whichever path it is handed — so the name and the layout are the
    /// app's, and nothing else writes here.
    static let folderName = "amiibo"

    static func folder(coreDirectory: URL) -> URL {
        coreDirectory.appendingPathComponent(folderName, isDirectory: true)
    }

    /// Every `.bin` in the folder, newest first. Reading it is a directory
    /// listing, so it costs nothing to repeat while the sheet is open.
    static func tags(coreDirectory: URL) -> [AmiiboTag] {
        let folder = self.folder(coreDirectory: coreDirectory)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            return []
        }
        return names
            .filter { $0.lowercased().hasSuffix(".bin") }
            .compactMap { name -> AmiiboTag? in
                let url = folder.appendingPathComponent(name)
                guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                      let size = attributes[.size] as? NSNumber else { return nil }
                return AmiiboTag(id: name,
                                 url: url,
                                 byteCount: size.int64Value,
                                 modified: attributes[.modificationDate] as? Date)
            }
            .sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
    }

    /// Copies one dump in from wherever the Files app keeps it. A name that is
    /// already taken gets a number rather than overwriting a tag the game may
    /// have written progress into.
    static func importTag(from source: URL, coreDirectory: URL) throws -> AmiiboTag {
        let manager = FileManager.default
        let folder = self.folder(coreDirectory: coreDirectory)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: nil)

        // A file handed over by the picker lives outside the app's container
        // until this is asked for.
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        let nameExtension = source.pathExtension.isEmpty ? "bin" : source.pathExtension
        let base = source.deletingPathExtension().lastPathComponent
        var destination = folder.appendingPathComponent("\(base).\(nameExtension)")
        var attempt = 2
        while manager.fileExists(atPath: destination.path) {
            destination = folder.appendingPathComponent("\(base) \(attempt).\(nameExtension)")
            attempt += 1
        }
        try manager.copyItem(at: source, to: destination)

        let attributes = (try? manager.attributesOfItem(atPath: destination.path)) ?? [:]
        return AmiiboTag(id: destination.lastPathComponent,
                         url: destination,
                         byteCount: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
                         modified: attributes[.modificationDate] as? Date)
    }

    static var state: AmiiboState {
        AmiiboState(rawValue: Int(AZCoreAmiiboCurrentState())) ?? .unavailable
    }

    /// YES when the core took the tag. It only takes one while the running game
    /// is scanning and the reader is empty, so a refusal is usually that rather
    /// than a bad file.
    static func load(_ tag: AmiiboTag) -> Bool {
        tag.url.path.withCString { AZCoreAmiiboLoad($0) == 1 }
    }

    static func remove() {
        AZCoreAmiiboRemove()
    }
}
