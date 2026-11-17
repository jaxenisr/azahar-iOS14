import Foundation

/// A title's custom texture pack: the folder the core scans, and what is in it.
///
/// The core does the loading; this type only describes what it will find. Every
/// rule below comes from the pinned core's own source at tag `2127.0-rc3`:
///
/// - packs live in `<user>/load/textures/{:016X}/`, the title id as sixteen
///   uppercase hex digits — the same id the cheat file is named for;
/// - `CustomTexManager::GetTextures` scans that folder recursively (up to 64
///   levels) and `ParseFilename` accepts only `.png`, `.dds` and `.ktx`, so
///   anything else in the folder is ignored rather than loaded;
/// - `pack.json` is optional. Without it `FindCustomTextures` sets the legacy
///   hash and skips mipmaps. With it, the only keys read are `options`
///   (`skip_mipmap`, `flip_png_files`, `use_new_hash`) and the `textures` map;
///   `author`, `version` and `description` are informational, which is all this
///   type shows them as;
/// - dumps are written to `<user>/dump/textures/{:016X}/`, a different folder
///   from the one packs are read from (`DumpDir`, not `LoadDir`).
///
/// A pack is a folder the user puts in place: nothing here writes or edits one.
struct TexturePack: Equatable {
    /// What `pack.json` says about the pack, for display only.
    struct Info: Equatable {
        var author: String?
        var version: String?
        var summary: String?
    }

    let titleID: String
    let directory: URL
    /// nil when the folder carries no `pack.json`, which is a valid pack.
    let info: Info?
    /// Files the core would try to load, counted by the extension rule above.
    let textureCount: Int
    let byteCount: Int64

    /// The folder names the core uses, from `FileUtil`'s `LOAD_DIR` and
    /// `DUMP_DIR`, both relative to the user directory (Documents/Azahar here).
    static let loadFolder = "load"
    static let dumpFolder = "dump"
    static let textureFileExtensions: Set<String> = ["png", "dds", "ktx"]

    /// `<user>/load/textures/<title id>/`
    static func directory(titleID: String, coreDirectory: URL) -> URL {
        coreDirectory
            .appendingPathComponent(loadFolder, isDirectory: true)
            .appendingPathComponent("textures", isDirectory: true)
            .appendingPathComponent(titleID, isDirectory: true)
    }

    /// `<user>/dump/textures/<title id>/`
    static func dumpDirectory(titleID: String, coreDirectory: URL) -> URL {
        coreDirectory
            .appendingPathComponent(dumpFolder, isDirectory: true)
            .appendingPathComponent("textures", isDirectory: true)
            .appendingPathComponent(titleID, isDirectory: true)
    }

    /// Reads one title's pack folder. nil means there is nothing to load: no
    /// folder, or a folder with no texture file in it. The core creates the folder
    /// itself on every boot (`GetTextures` calls `CreateFullPath`), so an existing
    /// folder on its own is not a pack.
    static func load(titleID: String, coreDirectory: URL) -> TexturePack? {
        let folder = directory(titleID: titleID, coreDirectory: coreDirectory)
        let manager = FileManager.default
        guard manager.fileExists(atPath: folder.path) else { return nil }

        var count = 0
        var bytes: Int64 = 0
        guard let walker = manager.enumerator(at: folder,
                                              includingPropertiesForKeys: [.fileSizeKey],
                                              options: [.skipsHiddenFiles],
                                              errorHandler: nil) else { return nil }
        for case let file as URL in walker {
            guard textureFileExtensions.contains(file.pathExtension.lowercased()) else { continue }
            count += 1
            if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                bytes += Int64(size)
            }
        }
        guard count > 0 else { return nil }
        return TexturePack(titleID: titleID,
                           directory: folder,
                           info: readInfo(in: folder),
                           textureCount: count,
                           byteCount: bytes)
    }

    /// How many textures the core has already dumped for this title, if it has ever
    /// run with dumping on. Read only: the dump folder is the core's to write.
    static func dumpedCount(titleID: String, coreDirectory: URL) -> Int {
        let folder = dumpDirectory(titleID: titleID, coreDirectory: coreDirectory)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            return 0
        }
        return names.filter { $0.lowercased().hasSuffix(".png") }.count
    }

    var sizeDescription: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: byteCount)
    }

    /// `pack.json` is read rather than validated: the core parses it with errors
    /// ignored, so a file this app cannot read is one the core would fall back on
    /// the legacy defaults for, which is exactly what nil reports.
    private static func readInfo(in folder: URL) -> Info? {
        let config = folder.appendingPathComponent("pack.json")
        guard let data = try? Data(contentsOf: config),
              let parsed = try? JSONSerialization.jsonObject(with: data),
              let object = parsed as? [String: Any] else {
            return nil
        }
        let info = Info(author: object["author"] as? String,
                        version: object["version"] as? String,
                        summary: object["description"] as? String)
        guard info.author != nil || info.version != nil || info.summary != nil else { return nil }
        return info
    }
}
