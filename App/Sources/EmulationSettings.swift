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

/// Which console the core pretends to be.
///
/// The core's option is `citra_is_new_3ds`, its values are `New 3DS` and
/// `Old 3DS`, and its **default is New 3DS** — so that is what this app has been
/// running, whether or not anyone chose it. New 3DS brings the faster CPU and the
/// extra memory some titles require; the original model is lighter, which matters
/// on a 3 GB device. Read at load, so a running game keeps the model it started
/// with.
enum ConsoleModel: String, Codable, CaseIterable, Identifiable {
    case new3DS = "New 3DS"
    case old3DS = "Old 3DS"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .new3DS: return "New 3DS"
        case .old3DS: return "Original 3DS"
        }
    }
}

/// The core's texture filter (`citra_texture_filter`).
///
/// Only the values the pinned core actually honours are offered. Two are left out
/// on purpose, both established by reading `src/citra_libretro/core_settings.cpp`
/// at tag `2127.0-rc3`:
///
/// - `Anime4K` is in the option list, but `GetTextureFilter` returns `NoFilter`
///   whenever the graphics API is Vulkan — and Vulkan is the only API this app
///   can present through on iOS;
/// - the parser compares against `"xBRZ freescale"` while the option list
///   advertises `"xBRZ"`, so that choice can never be applied either.
///
/// A row that cannot change the picture is worse than no row, so neither is
/// offered. Read at load, with the rest of the graphics options.
enum TextureFilter: String, Codable, CaseIterable, Identifiable {
    case none = "none"
    case bicubic = "Bicubic"
    case scaleForce = "ScaleForce"
    case mmpX = "MMPX"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None"
        case .bicubic: return "Bicubic"
        case .scaleForce: return "ScaleForce"
        case .mmpX: return "MMPX"
        }
    }
}

/// One playback's settings: global defaults with any per-game overrides already
/// applied.
struct EmulationSettings: Codable, Equatable {
    /// The value each setting falls back to when nothing was chosen. A stored nil
    /// means exactly that — not chosen — so the row can read `Default` and the
    /// menu can tick it, instead of showing the default as though it were a
    /// choice someone had made.
    enum Default {
        static let resolutionScale = 1
        static let layout: PlaybackLayout = .stacked
        static let speed: PlaybackSpeed = .normal
        static let cpuClockPercent = 100
        static let region: PlaybackRegion = .automatic
        static let consoleModel: ConsoleModel = .new3DS
        static let textureFilter: TextureFilter = .none
    }

    /// nil: never chosen. The app uses `Default` and says so.
    var resolutionScale: Int?
    var layout: PlaybackLayout?
    var speed: PlaybackSpeed?
    var cpuClockPercent: Int?
    /// Read at boot by the core; `Automatic` is what every title used before this
    /// setting existed.
    var region: PlaybackRegion?
    /// The console the core emulates. `New 3DS` is the core's own default, so the
    /// untouched state is what this app has always played at.
    var consoleModel: ConsoleModel?
    var textureFilter: TextureFilter?
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
    /// keeps its other settings when a field is added — these settings live in a
    /// file already on people's devices. Synthesised decoding throws on the
    /// missing key, and the load would silently fall back to defaults.
    ///
    /// A stored value equal to the built-in default is read back as "not chosen":
    /// earlier builds wrote the default into storage whether or not anyone had
    /// picked it, and after this change that must not read as a choice.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        resolutionScale = EmulationSettings.chosen(try container.decodeIfPresent(Int.self, forKey: .resolutionScale),
                                                   Default.resolutionScale)
        layout = EmulationSettings.chosen(try container.decodeIfPresent(PlaybackLayout.self, forKey: .layout),
                                          Default.layout)
        speed = EmulationSettings.chosen(try container.decodeIfPresent(PlaybackSpeed.self, forKey: .speed),
                                         Default.speed)
        cpuClockPercent = EmulationSettings.chosen(try container.decodeIfPresent(Int.self, forKey: .cpuClockPercent),
                                                   Default.cpuClockPercent)
        region = EmulationSettings.chosen(try container.decodeIfPresent(PlaybackRegion.self, forKey: .region),
                                          Default.region)
        consoleModel = EmulationSettings.chosen(try container.decodeIfPresent(ConsoleModel.self, forKey: .consoleModel),
                                                Default.consoleModel)
        textureFilter = EmulationSettings.chosen(try container.decodeIfPresent(TextureFilter.self, forKey: .textureFilter),
                                                 Default.textureFilter)
        volume = try container.decodeIfPresent(Double.self, forKey: .volume) ?? 0.8
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        hapticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? true
        controlsOpacity = try container.decodeIfPresent(Double.self, forKey: .controlsOpacity) ?? 0.9
        controlsScale = try container.decodeIfPresent(Double.self, forKey: .controlsScale) ?? 1.0
        customControlsEnabled = try container.decodeIfPresent(Bool.self, forKey: .customControlsEnabled) ?? false
        controlPreset = try container.decodeIfPresent(ControlPreset.self, forKey: .controlPreset) ?? .classic
    }

    private enum CodingKeys: String, CodingKey {
        case resolutionScale, layout, speed, cpuClockPercent, region, consoleModel, textureFilter
        case volume, isMuted, hapticsEnabled, controlsOpacity, controlsScale
        case customControlsEnabled, controlPreset
    }

    private static func chosen<Value: Equatable>(_ stored: Value?, _ fallback: Value) -> Value? {
        guard let stored = stored, stored != fallback else { return nil }
        return stored
    }

    // MARK: - Values to use

    /// What the core is given, and what a title plays with. These are the only
    /// places the fallback is applied, so "Default" and the value written into a
    /// core option can never disagree.

    var effectiveResolutionScale: Int {
        min(max(resolutionScale ?? Default.resolutionScale, 1), 4)
    }

    var effectiveLayout: PlaybackLayout { layout ?? Default.layout }
    var effectiveSpeed: PlaybackSpeed { speed ?? Default.speed }

    var effectiveClock: Int {
        guard let percent = cpuClockPercent, EmulationSettings.cpuClockChoices.contains(percent) else {
            return Default.cpuClockPercent
        }
        return percent
    }

    var effectiveRegion: PlaybackRegion { region ?? Default.region }
    var effectiveConsoleModel: ConsoleModel { consoleModel ?? Default.consoleModel }
    var effectiveTextureFilter: TextureFilter { textureFilter ?? Default.textureFilter }

    var clampedOpacity: Double { min(max(controlsOpacity, 0.25), 1.0) }
    var clampedScale: Double { min(max(controlsScale, 0.7), 1.35) }
}
