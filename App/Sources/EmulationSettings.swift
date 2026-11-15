import Foundation
import CoreGraphics

/// How the 3DS's two screens are arranged in the frame the core produces.
/// These are the core's own layout options (`citra_layout_option`), so the core
/// composes the frame and the present path only has to keep its aspect ratio.
enum PlaybackLayout: String, Codable, CaseIterable, Identifiable {
    case largeScreen = "large_screen"
    case sideBySide = "side_by_side"
    case topOnly = "single_screen"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .largeScreen: return "Top large"
        case .sideBySide: return "Side by side"
        case .topOnly: return "Top only"
        }
    }
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

/// One playback's settings: global defaults with any per-game overrides already
/// applied.
struct EmulationSettings: Codable, Equatable {
    var resolutionScale: Int = 1
    var layout: PlaybackLayout = .largeScreen
    var speed: PlaybackSpeed = .normal
    var cpuClockPercent: Int = 100
    var volume: Double = 0.8
    var isMuted: Bool = false
    var hapticsEnabled: Bool = true
    var controlsOpacity: Double = 0.9
    var controlsScale: Double = 1.0

    static let cpuClockChoices = [25, 50, 75, 100, 125, 150, 175, 200]

    var clampedResolution: Int { min(max(resolutionScale, 1), 4) }
    var clampedClock: Int {
        EmulationSettings.cpuClockChoices.contains(cpuClockPercent) ? cpuClockPercent : 100
    }
    var clampedOpacity: Double { min(max(controlsOpacity, 0.25), 1.0) }
    var clampedScale: Double { min(max(controlsScale, 0.7), 1.35) }
}
