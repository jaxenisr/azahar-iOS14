import Foundation
import UIKit
import Combine

/// Global settings, per-game overrides, and the numbers the storage screen shows.
///
/// Overrides are stored separately from the global values so a title can differ
/// from the defaults without the defaults being rewritten, and so "use global"
/// is always one tap away.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    struct Global: Codable, Equatable {
        var emulation = EmulationSettings()
    }

    struct GameOverride: Codable, Equatable {
        var resolutionScale: Int?
        var layout: PlaybackLayout?
        var speed: PlaybackSpeed?
        var cpuClockPercent: Int?

        var isEmpty: Bool {
            resolutionScale == nil && layout == nil && speed == nil && cpuClockPercent == nil
        }
    }

    struct StorageUsage {
        var romsBytes: Int64 = 0
        var saveDataBytes: Int64 = 0
        var stateBytes: Int64 = 0
        var cacheBytes: Int64 = 0

        var totalBytes: Int64 { romsBytes + saveDataBytes + stateBytes + cacheBytes }

        static func format(_ bytes: Int64) -> String {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB, .useGB]
            formatter.countStyle = .file
            return formatter.string(fromByteCount: max(bytes, 0))
        }
    }

    @Published private(set) var global = Global()
    @Published private(set) var overrides: [String: GameOverride] = [:]

    private let defaults = UserDefaults.standard
    private let globalKey = "azahar.settings.global.v1"
    private let overridesKey = "azahar.settings.overrides.v1"
    private let layoutMigrationKey = "azahar.settings.stackedDefault.v1"

    private init() {
        load()
    }

    // MARK: - Reading

    /// The settings a title should play with: the global values with any override
    /// applied on top.
    func settings(for gameID: String) -> EmulationSettings {
        var result = global.emulation
        guard let game = overrides[gameID] else { return result }
        if let value = game.resolutionScale { result.resolutionScale = value }
        if let value = game.layout { result.layout = value }
        if let value = game.speed { result.speed = value }
        if let value = game.cpuClockPercent { result.cpuClockPercent = value }
        return result
    }

    func override(for gameID: String) -> GameOverride {
        overrides[gameID] ?? GameOverride()
    }

    func hasOverride(for gameID: String) -> Bool {
        !(overrides[gameID]?.isEmpty ?? true)
    }

    // MARK: - Writing

    func updateGlobal(_ body: (inout EmulationSettings) -> Void) {
        body(&global.emulation)
        save()
    }

    func setOverride(_ override: GameOverride, for gameID: String) {
        if override.isEmpty {
            overrides.removeValue(forKey: gameID)
        } else {
            overrides[gameID] = override
        }
        save()
    }

    func clearOverride(for gameID: String) {
        overrides.removeValue(forKey: gameID)
        save()
    }

    // MARK: - Storage

    func storageUsage(romsDirectory: URL, coreDirectory: URL) -> StorageUsage {
        var usage = StorageUsage()
        usage.romsBytes = directorySize(romsDirectory, extensions: GameLibrary.romExtensions)
        usage.saveDataBytes = directorySize(coreDirectory.appendingPathComponent("nand", isDirectory: true))
        usage.stateBytes = directorySize(coreDirectory.appendingPathComponent("savestates", isDirectory: true))
        usage.cacheBytes = directorySize(coreDirectory.appendingPathComponent("cache", isDirectory: true))
        return usage
    }

    /// Azahar keeps its disk shader pipeline cache under its user directory; this
    /// is that folder and nothing else.
    @discardableResult
    func clearShaderCache(coreDirectory: URL) -> String {
        let cache = coreDirectory.appendingPathComponent("cache", isDirectory: true)
        guard FileManager.default.fileExists(atPath: cache.path) else {
            return "There is no shader cache to clear yet."
        }
        let before = directorySize(cache)
        do {
            try FileManager.default.removeItem(at: cache)
            return "Cleared \(StorageUsage.format(before)) of shader cache."
        } catch {
            return "The cache could not be cleared: \(error.localizedDescription)"
        }
    }

    func directorySize(_ url: URL, extensions: [String]? = nil) -> Int64 {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(at: url,
                                                  includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                                  options: [.skipsHiddenFiles],
                                                  errorHandler: nil) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let extensions = extensions {
                let suffix = fileURL.pathExtension.lowercased()
                if !extensions.contains(suffix) { continue }
            }
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    // MARK: - Persistence

    private func load() {
        if let data = defaults.data(forKey: globalKey),
           let decoded = try? JSONDecoder().decode(Global.self, from: data) {
            global = decoded
        }
        if let data = defaults.data(forKey: overridesKey),
           let decoded = try? JSONDecoder().decode([String: GameOverride].self, from: data) {
            overrides = decoded
        }

        // Titles now start stacked, the way the console is held. A stored global
        // that is still the previous default is moved over once, so an update
        // does not need the setting to be found and changed by hand. A layout
        // picked deliberately — anything other than the old default — is left
        // alone, and per-title overrides are untouched.
        if !defaults.bool(forKey: layoutMigrationKey) {
            defaults.set(true, forKey: layoutMigrationKey)
            if global.emulation.layout == .largeScreen {
                global.emulation.layout = .stacked
                save()
            }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(global) {
            defaults.set(data, forKey: globalKey)
        }
        if let data = try? JSONEncoder().encode(overrides) {
            defaults.set(data, forKey: overridesKey)
        }
    }
}
