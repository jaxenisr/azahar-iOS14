import Foundation
import UIKit

struct GameEntry: Identifiable, Equatable {
    let id: String
    let url: URL
    let title: String
    let icon: UIImage?
    let subtitle: String

    static func == (lhs: GameEntry, rhs: GameEntry) -> Bool {
        lhs.id == rhs.id
    }
}

final class GameLibrary: ObservableObject {
    static let romExtensions = ["3ds", "cci", "zcci"]

    @Published private(set) var games: [GameEntry] = []
    @Published private(set) var isBusy = false
    @Published var message: String?
    @Published private(set) var coreDescription = "not checked"
    @Published private(set) var coreStatus = "not checked"

    /// Documents/Azahar is the core's user directory: system files go here.
    let coreDirectory: URL
    let romsDirectory: URL

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.jaxenisr.azaharipad.library",
                                      qos: .userInitiated)
    private var coreChecked = false

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        romsDirectory = documents.appendingPathComponent("ROMs", isDirectory: true)
        coreDirectory = documents.appendingPathComponent("Azahar", isDirectory: true)

        for directory in [romsDirectory, coreDirectory] {
            try? fileManager.createDirectory(at: directory,
                                             withIntermediateDirectories: true,
                                             attributes: nil)
        }
    }

    // MARK: - Library

    func reload() {
        isBusy = true
        queue.async { [weak self] in
            guard let self = self else { return }
            let entries = self.scan()
            DispatchQueue.main.async {
                self.games = entries
                self.isBusy = false
            }
        }
    }

    func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        isBusy = true
        queue.async { [weak self] in
            guard let self = self else { return }
            var failures: [String] = []

            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }

                let destination = self.romsDirectory.appendingPathComponent(url.lastPathComponent)
                do {
                    if self.fileManager.fileExists(atPath: destination.path) {
                        try self.fileManager.removeItem(at: destination)
                    }
                    try self.fileManager.copyItem(at: url, to: destination)
                } catch {
                    failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }

            let entries = self.scan()
            DispatchQueue.main.async {
                self.games = entries
                self.isBusy = false
                self.message = failures.isEmpty ? nil : failures.joined(separator: "\n")
            }
        }
    }

    func remove(_ game: GameEntry) {
        try? fileManager.removeItem(at: game.url)
        reload()
    }

    private func scan() -> [GameEntry] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: romsDirectory.path) else {
            return []
        }
        var entries: [GameEntry] = []

        for name in names.sorted() {
            guard !name.hasPrefix(".") else { continue }
            let ext = (name as NSString).pathExtension.lowercased()
            guard GameLibrary.romExtensions.contains(ext) else { continue }

            let url = romsDirectory.appendingPathComponent(name)
            var size: Int64 = 0
            if let attributes = try? fileManager.attributesOfItem(atPath: url.path),
               let number = attributes[.size] as? NSNumber {
                size = number.int64Value
            }

            let metadata = ROMReader.read(url: url, fileExtension: ext)
            let title = metadata.title ?? url.deletingPathExtension().lastPathComponent
            let subtitle = "\(ext.uppercased())  ·  \(GameLibrary.format(size))"
            entries.append(GameEntry(id: name,
                                     url: url,
                                     title: title,
                                     icon: metadata.icon,
                                     subtitle: subtitle))
        }
        return entries
    }

    // MARK: - Content requirements

    struct CoreFileStatus: Identifiable {
        let id: String
        let note: String
        let present: Bool
    }

    /// What the core reads from its own user directory beyond the ROM. These are
    /// the paths Azahar uses; whether each one exists is the only claim this screen
    /// makes, and the core still has the final say when it loads the content.
    func coreFileStatus() -> [CoreFileStatus] {
        func exists(_ relative: String) -> Bool {
            fileManager.fileExists(atPath: coreDirectory.appendingPathComponent(relative).path)
        }
        return [
            CoreFileStatus(id: "sysdata",
                           note: "system archives (font, region, console data)",
                           present: exists("sysdata")),
            CoreFileStatus(id: "nand",
                           note: "emulated console storage and save data",
                           present: exists("nand")),
            CoreFileStatus(id: "sysdata/aes_keys.txt",
                           note: "decryption keys, only needed for encrypted dumps",
                           present: exists("sysdata/aes_keys.txt")),
            CoreFileStatus(id: "sysdata/seeddb.bin",
                           note: "title seeds, only needed for seeded eShop content",
                           present: exists("sysdata/seeddb.bin"))
        ]
    }

    // MARK: - Core

    /// Initialises and immediately shuts down the linked core. This exists to
    /// prove the statically linked engine loads and runs on the device before the
    /// emulation loop is built on top of it.
    func runCoreCheck() {
        guard !coreChecked else { return }
        coreChecked = true

        let description = AZCoreDescribe()
        coreDescription = description

        let initialised = AZCoreInitialize(coreDirectory.path, coreDirectory.path)
        if initialised {
            AZCoreShutdown()
            coreStatus = "core initialised and shut down cleanly"
        } else {
            coreStatus = AZCoreLastError() ?? "core failed to initialise"
        }
    }

    private static func format(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
