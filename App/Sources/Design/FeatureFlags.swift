import Foundation

/// Settings the interface will show before the app can honour them.
///
/// A greyed row that says what is missing is honest and doubles as a roadmap; a
/// hidden option is neither. Every one of these renders through `DesignRow` with
/// its control disabled, and each is switched on by flipping a single line in
/// `isAvailable`.
///
/// Nothing here is a PlayStation option: this list is the 3DS core's own set.
enum PlannedFeature: String, CaseIterable, Identifiable {
    /// Region: the core option exists, the UI and the per-title override do not.
    case regionOverride
    /// New 3DS mode: the core option exists, nothing in the app writes it yet.
    case new3DSMode
    /// Texture filter: the core option exists under two names, no UI mapping yet.
    case textureFilter
    /// Cheats: the core has no cheat loader wired in this build.
    case cheats
    /// Custom texture packs: not wired, and the memory cost is a real risk on 3 GB.
    case texturePacks
    /// Camera feed for amiibo photos: no capture session, no core surface for it.
    case cameraFeed
    /// Artic Base: the core can stream from a real 3DS, there is no connection UI.
    case articBase
    /// CPU JIT: needs a TrollStore JIT entitlement the app does not request.
    case cpuJIT

    var id: String { rawValue }

    /// The row's title, as it will read on the settings screen.
    var title: String {
        switch self {
        case .regionOverride: return "Region"
        case .new3DSMode: return "New 3DS mode"
        case .textureFilter: return "Texture filter"
        case .cheats: return "Cheats"
        case .texturePacks: return "Texture packs"
        case .cameraFeed: return "Camera"
        case .articBase: return "Artic Base"
        case .cpuJIT: return "CPU JIT"
        }
    }

    /// What is missing, in one line. This is the subtitle a placeholder row shows
    /// under its title, so it has to be true rather than reassuring.
    var missing: String {
        switch self {
        case .regionOverride:
            return "Core option exists, the picker is not wired"
        case .new3DSMode:
            return "Core option exists, the app never sets it"
        case .textureFilter:
            return "Core option exists, no UI mapping"
        case .cheats:
            return "No cheat loader in this build"
        case .texturePacks:
            return "Not wired, and memory-heavy on 3 GB"
        case .cameraFeed:
            return "No capture session in the app"
        case .articBase:
            return "Core can stream, no connection UI"
        case .cpuJIT:
            return "Needs a JIT entitlement the app does not request"
        }
    }

    /// The one line to change when a feature is wired up.
    var isAvailable: Bool {
        switch self {
        case .regionOverride: return false
        case .new3DSMode: return false
        case .textureFilter: return false
        case .cheats: return false
        case .texturePacks: return false
        case .cameraFeed: return false
        case .articBase: return false
        case .cpuJIT: return false
        }
    }

    /// The subtitle to render under the row: its own explanation while it is a
    /// placeholder, nothing once it is real.
    var subtitle: String? {
        isAvailable ? nil : missing
    }
}
