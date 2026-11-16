import Foundation
import CoreGraphics

/// How the 3DS's two screens are arranged in the frame the core produces.
/// These are the core's own layout options (`citra_layout_option`), so the core
/// composes the frame and the present path only has to keep its aspect ratio.
enum PlaybackLayout: String, Codable, CaseIterable, Identifiable {
    case largeScreen = "large_screen"
    case sideBySide = "side_by_side"
    case topOnly = "single_screen"
    /// The core's `default` option: the top screen, then the bottom screen
    /// directly beneath it at its own smaller size, both on one vertical axis,
    /// exactly as the hardware holds them. Stacked is how the console is meant
    /// to be held, so it is the default a title starts with.
    case stacked = "default"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .largeScreen: return "Top large"
        case .sideBySide: return "Side by side"
        case .topOnly: return "Top only"
        case .stacked: return "Stacked"
        }
    }

    /// Hinge between the two screens in `stacked`, as a fraction of the height
    /// the pair occupies on screen. The core composes the two screens flush (its
    /// `screen_gap` is 0, and the libretro core exposes no option for it), so the
    /// present path draws the halves with this gap between them: about 10 pt on a
    /// 500 pt pair, and proportional at any other size.
    static let stackedHinge: CGFloat = 0.02

    /// Aspect of the pair as it is presented in `stacked`: each screen is 400x240,
    /// so the two together are 400x480, plus the hinge. Other layouts are presented
    /// at whatever geometry the core reports for them.
    static let stackedAspect: CGFloat = (1 - stackedHinge) / 1.2
}

/// How fast the emulation thread is allowed to run.
///
/// A 3DS frame is 16.7 ms of work; this decides how much wall time each of those
/// frames gets. `unlimited` removes the pacing sleep entirely, so the figure the
/// overlay shows is what the core can actually do rather than what the limiter
/// permits.
enum PlaybackSpeed: Double, Codable, CaseIterable, Identifiable {
    case half = 0.5
    case threeQuarters = 0.75
    case normal = 1.0
    case unlimited = 0

    var id: Double { rawValue }

    var title: String {
        switch self {
        case .half: return "50%"
        case .threeQuarters: return "75%"
        case .normal: return "100%"
        case .unlimited: return "Unlimited"
        }
    }

    /// Pacing multiplier, or nil when the core should run unpaced.
    var pacingMultiplier: Double? {
        self == .unlimited ? nil : rawValue
    }

    static func from(_ value: Double) -> PlaybackSpeed {
        if value <= 0 { return .unlimited }
        return PlaybackSpeed(rawValue: value) ?? .normal
    }
}

/// Which market the emulated console reports itself as.
///
/// Region locking is the console's own, not the emulator's: a title that checks it
/// refuses to boot when the two disagree. These strings are exactly the values the
/// core accepts for `citra_region_value`, and `Auto` is the core's default, which
/// picks the region from the title's own header. So the default here changes
/// nothing for a title that was already playing.
enum PlaybackRegion: String, Codable, CaseIterable, Identifiable {
    case automatic = "Auto"
    case japan = "Japan"
    case usa = "USA"
    case europe = "Europe"
    case australia = "Australia"
    case china = "China"
    case korea = "Korea"
    case taiwan = "Taiwan"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .japan: return "Japan"
        case .usa: return "USA"
        case .europe: return "Europe"
        case .australia: return "Australia"
        case .china: return "China"
        case .korea: return "Korea"
        case .taiwan: return "Taiwan"
        }
    }
}

/// One playback's settings: global defaults with any per-game overrides already
/// applied.
struct EmulationSettings: Codable, Equatable {
    var resolutionScale: Int = 1
    var layout: PlaybackLayout = .stacked
    var speed: PlaybackSpeed = .normal
    var cpuClockPercent: Int = 100
    /// Read at boot by the core; `Automatic` is what every title used before this
    /// setting existed.
    var region: PlaybackRegion = .automatic
    var volume: Double = 0.8
    var isMuted: Bool = false
    var hapticsEnabled: Bool = true
    var controlsOpacity: Double = 0.9
    var controlsScale: Double = 1.0

    /// The experimental control layout. Off by default: the standard layout stays
    /// the one a fresh install gets, and turning this on is a deliberate act.
    var customControlsEnabled: Bool = false
    var controlPreset: ControlPreset = .classic

    static let cpuClockChoices = [25, 50, 75, 100, 125, 150, 175, 200]

    init() {}

    /// Every field is optional on disk so that a value stored by an earlier build
    /// keeps its other settings when a field is added — this setting was added to
    /// a file already on people's devices. Synthesised decoding throws on the
    /// missing key, and the load would silently fall back to defaults.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        resolutionScale = try container.decodeIfPresent(Int.self, forKey: .resolutionScale) ?? 1
        layout = try container.decodeIfPresent(PlaybackLayout.self, forKey: .layout) ?? .stacked
        speed = try container.decodeIfPresent(PlaybackSpeed.self, forKey: .speed) ?? .normal
        cpuClockPercent = try container.decodeIfPresent(Int.self, forKey: .cpuClockPercent) ?? 100
        region = try container.decodeIfPresent(PlaybackRegion.self, forKey: .region) ?? .automatic
        volume = try container.decodeIfPresent(Double.self, forKey: .volume) ?? 0.8
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        hapticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? true
        controlsOpacity = try container.decodeIfPresent(Double.self, forKey: .controlsOpacity) ?? 0.9
        controlsScale = try container.decodeIfPresent(Double.self, forKey: .controlsScale) ?? 1.0
        customControlsEnabled = try container.decodeIfPresent(Bool.self, forKey: .customControlsEnabled) ?? false
        controlPreset = try container.decodeIfPresent(ControlPreset.self, forKey: .controlPreset) ?? .classic
    }

    private enum CodingKeys: String, CodingKey {
        case resolutionScale, layout, speed, cpuClockPercent, region
        case volume, isMuted, hapticsEnabled, controlsOpacity, controlsScale
        case customControlsEnabled, controlPreset
    }

    var clampedResolution: Int { min(max(resolutionScale, 1), 4) }
    var clampedClock: Int {
        EmulationSettings.cpuClockChoices.contains(cpuClockPercent) ? cpuClockPercent : 100
    }
    var clampedOpacity: Double { min(max(controlsOpacity, 0.25), 1.0) }
    var clampedScale: Double { min(max(controlsScale, 0.7), 1.35) }
}
