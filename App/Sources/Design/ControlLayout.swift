import SwiftUI
import Combine
import CoreGraphics

/// The experimental control layout.
///
/// The standard layout is what the app ships with, and nothing here changes it
/// unless the toggle is on. What this does is take the frames `PlaybackLayout`
/// already computes and move them: a preset, then a per-title nudge, then a
/// clamp that keeps every control out of the picture.

// MARK: - Presets

enum ControlPreset: String, Codable, CaseIterable, Identifiable {
    /// What the app does today.
    case classic
    /// Stick and D-pad further out to the left, face buttons further right.
    case split
    /// Smaller controls, shoulders dropped to the bottom edge.
    case minimal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .split: return "Split"
        case .minimal: return "Minimal"
        }
    }

    /// Says what it does, so the chip row is not a guessing game.
    var blurb: String {
        switch self {
        case .classic:
            return "What the app does today: stick and D-pad on the left, diamond on the right."
        case .split:
            return "Pushed apart: stick and D-pad further out, diamond further right."
        case .minimal:
            return "Smaller controls, shoulders moved down to the bottom edge."
        }
    }
}

// MARK: - Nudges

/// A per-control nudge in points, applied on top of the preset.
struct ControlOffset: Codable, Equatable {
    var x: Double = 0
    var y: Double = 0

    static let zero = ControlOffset()

    var isZero: Bool { x == 0 && y == 0 }
}

enum ControlSlot: String, Codable, CaseIterable, Identifiable {
    case stick
    case dpad
    case face
    case shoulderL
    case shoulderR
    case start
    case select

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stick: return "Stick"
        case .dpad: return "D-pad"
        case .face: return "A B X Y"
        case .shoulderL: return "L"
        case .shoulderR: return "R"
        case .start: return "Start"
        case .select: return "Select"
        }
    }
}

// MARK: - Engine

/// Moves the frames, then refuses to let any of them sit on the picture.
///
/// The rule that matters: a control may be nudged anywhere, and the clamp will
/// still push it back off the game image. A layout that can cover the picture is
/// a layout that loses races it cannot see.
enum ControlLayoutEngine {
    /// Space between a control and the edge of the surface.
    static let edgeMargin: CGFloat = 8
    /// How far a nudge can be dragged, so a slip of the finger cannot throw a
    /// button off the screen.
    static let maxNudge: CGFloat = 96

    static func apply(preset: ControlPreset,
                      offsets: [String: ControlOffset],
                      to setup: inout PlaybackInputView.Setup) {
        let image = setup.image
        let bounds = envelope(of: setup).insetBy(dx: -edgeMargin, dy: -edgeMargin)
        guard bounds.width > 0, bounds.height > 0 else { return }

        setup.stick = adjusted(.stick, rect: setup.stick, preset: preset, offsets: offsets,
                               bounds: bounds, image: image)
        setup.dpad = adjusted(.dpad, rect: setup.dpad, preset: preset, offsets: offsets,
                              bounds: bounds, image: image)
        setup.diamond = adjusted(.face, rect: setup.diamond, preset: preset, offsets: offsets,
                                 bounds: bounds, image: image)
        setup.shoulderL = adjusted(.shoulderL, rect: setup.shoulderL, preset: preset, offsets: offsets,
                                   bounds: bounds, image: image)
        setup.shoulderR = adjusted(.shoulderR, rect: setup.shoulderR, preset: preset, offsets: offsets,
                                   bounds: bounds, image: image)
        setup.start = adjusted(.start, rect: setup.start, preset: preset, offsets: offsets,
                               bounds: bounds, image: image)
        setup.select = adjusted(.select, rect: setup.select, preset: preset, offsets: offsets,
                                bounds: bounds, image: image)
    }

    /// The area the controls live in: everything the layout gave us, plus a
    /// little, which is a stand-in for the whole surface without needing it.
    static func envelope(of setup: PlaybackInputView.Setup) -> CGRect {
        var rect = setup.image
        for frame in [setup.stick, setup.dpad, setup.diamond,
                      setup.shoulderL, setup.shoulderR, setup.start, setup.select] {
            guard frame.width > 0, frame.height > 0 else { continue }
            rect = rect.union(frame)
        }
        return rect
    }

    private static func adjusted(_ slot: ControlSlot,
                                 rect: CGRect,
                                 preset: ControlPreset,
                                 offsets: [String: ControlOffset],
                                 bounds: CGRect,
                                 image: CGRect) -> CGRect {
        guard rect.width > 0, rect.height > 0 else { return rect }
        var r = presetRect(rect, slot: slot, preset: preset, image: image)

        let nudge = offsets[slot.rawValue] ?? .zero
        r.origin.x += CGFloat(min(max(nudge.x, -Double(maxNudge)), Double(maxNudge)))
        r.origin.y += CGFloat(min(max(nudge.y, -Double(maxNudge)), Double(maxNudge)))

        return clamped(r, inside: bounds, avoiding: image)
    }

    private static func presetRect(_ rect: CGRect,
                                   slot: ControlSlot,
                                   preset: ControlPreset,
                                   image: CGRect) -> CGRect {
        switch preset {
        case .classic:
            return rect
        case .split:
            let push = image.width * 0.04
            switch slot {
            case .stick, .dpad:
                return rect.offsetBy(dx: -push, dy: 0)
            case .face:
                return rect.offsetBy(dx: push, dy: 0)
            default:
                return rect
            }
        case .minimal:
            var shrunk = rect.insetBy(dx: rect.width * 0.075, dy: rect.height * 0.075)
            // Inset keeps the centre, which is what a smaller control should do.
            switch slot {
            case .shoulderL, .shoulderR, .start, .select:
                shrunk.origin.y += 12
            default:
                break
            }
            return shrunk
        }
    }

    private static func clamped(_ rect: CGRect, inside bounds: CGRect, avoiding image: CGRect) -> CGRect {
        var r = rect
        r.origin.x = min(max(r.minX, bounds.minX), max(bounds.maxX - r.width, bounds.minX))
        r.origin.y = min(max(r.minY, bounds.minY), max(bounds.maxY - r.height, bounds.minY))

        // A zero-sized image is a layout that has not decided yet; nothing to avoid.
        guard image.width > 1, image.height > 1, r.intersects(image) else { return r }

        // Push out along the shallower overlap, so a control slides off the side
        // it is already closest to instead of jumping across the picture.
        let fromLeft = r.maxX - image.minX
        let fromRight = image.maxX - r.minX
        let fromTop = r.maxY - image.minY
        let fromBottom = image.maxY - r.minY

        if min(fromLeft, fromRight) < min(fromTop, fromBottom) {
            r.origin.x += fromLeft < fromRight ? -fromLeft : fromRight
        } else {
            r.origin.y += fromTop < fromBottom ? -fromTop : fromBottom
        }

        // Moving it may have taken it past the edge; keep it on the surface.
        r.origin.x = min(max(r.minX, bounds.minX), max(bounds.maxX - r.width, bounds.minX))
        r.origin.y = min(max(r.minY, bounds.minY), max(bounds.maxY - r.height, bounds.minY))
        return r
    }
}

// MARK: - Settings card

/// The switch, the preset and the counters, together, because a layout nobody
/// can measure is a layout nobody should trust.
struct ExperimentalControlsCard: View {
    @ObservedObject private var store = SettingsStore.shared

    private var settings: EmulationSettings { store.global.emulation }

    var body: some View {
        SettingsCard("Controls (experimental)",
                     subtitle: "Off by default. The standard controls stay in charge until you turn this on.") {
            SettingRow("Custom layout",
                       subtitle: settings.customControlsEnabled
                        ? "On: presets and nudges apply when a game runs"
                        : "Off: the standard layout is used") {
                SettingsToggle(isOn: settings.customControlsEnabled) { value in
                    store.updateGlobal { $0.customControlsEnabled = value }
                }
            }

            RowDivider()

            SettingRow("Preset",
                       subtitle: settings.controlPreset.blurb,
                       isAvailable: settings.customControlsEnabled) {
                SegmentedRow(options: ControlPreset.allCases.map { $0.title },
                             selection: ControlPreset.allCases.firstIndex(of: settings.controlPreset) ?? 0) { index in
                    store.updateGlobal { $0.controlPreset = ControlPreset.allCases[index] }
                }
            }

            if settings.customControlsEnabled {
                RowDivider()
                TouchCounterRow()
            }
        }
    }
}

/// Taps, polls and pressed frames, live. The same three numbers as the
/// diagnostics sheet, read from the same places, refreshed once a second while a
/// game is running: tap the lower screen and they have to move.
struct TouchCounterRow: View {
    @State private var taps = 0
    @State private var polls: UInt64 = 0
    @State private var pressedFrames: UInt64 = 0

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        SettingRow("Touch",
                   subtitle: "Taps \(taps) · Polls \(polls) · Pressed frames \(pressedFrames)") {
            Text(pressedFrames > 0 ? "live" : "waiting")
                .font(Design.Fonts.caption.weight(.semibold))
                .foregroundColor(pressedFrames > 0 ? Design.Palette.positive : Design.Palette.secondaryInk)
        }
        .onAppear(perform: refresh)
        .onReceive(ticker) { _ in refresh() }
    }

    private func refresh() {
        var polls: UInt64 = 0
        var pressedFrames: UInt64 = 0
        AZCorePointerStats(&polls, &pressedFrames)
        self.polls = polls
        self.pressedFrames = pressedFrames
        self.taps = TouchSurfaceView.taps
    }
}
