import SwiftUI
import AVFoundation

/// The audio path as the device sees it.
///
/// This is the screen to open when there is no sound, because the two questions
/// that matter are answered separately here: is the core producing anything, and
/// is the engine consuming it. When the graph never came up, the exception that
/// stopped it is named, with the reason AVFAudio gave.
///
/// The touch path is here for the same reason: it is three short stages — the tap
/// arriving, the core asking for a pointer, the core seeing a press — and the
/// counters say which stage is silent.
///
/// The sheet keeps the player's dark backdrop but its cards are the app's white
/// ones, so every value inside a card is drawn in dark ink. The header is the only
/// text on the backdrop, and it stays light.
struct AudioDiagnosticsView: View {
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject private var store = SettingsStore.shared

    @State private var counters = AudioOutput.Counters()
    @State private var sessionInfo = SessionInfo()
    @State private var rates = Rates()
    @State private var callbacksTotal: UInt64 = 0
    @State private var baseline: Baseline?
    @State private var touch = TouchCounters()

    private struct SessionInfo {
        var category = "—"
        var route = "—"
        var hardwareRate: Double = 0
        var channels = 0
    }

    private struct Rates {
        var callbacks: Double = 0
        var produced: Double = 0
        var consumed: Double = 0
    }

    private struct TouchCounters {
        var taps = 0
        var polls: UInt64 = 0
        var pressedFrames: UInt64 = 0
    }

    private struct Baseline {
        var callbacks: UInt64
        var produced: UInt64
        var consumed: UInt64
        var time: Date
    }

    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Theme.backgroundSpotlight.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    header

                    if !counters.available {
                        failureCard
                    }

                    SettingsCard("Session") {
                        row("Graph", counters.available ? "built" : "refused",
                            tint: counters.available ? Design.Palette.ink : .orange)
                        row("State", counters.state)
                        row("Category", sessionInfo.category)
                        row("Route", sessionInfo.route)
                        row("Hardware", sessionInfo.hardwareRate > 0
                            ? String(format: "%.0f Hz · %.0f ch", sessionInfo.hardwareRate, Double(sessionInfo.channels))
                            : "unknown")
                    }

                    SettingsCard("Pipeline") {
                        row("Core rate", String(format: "%.0f Hz", counters.coreSampleRate))
                        row("Engine", counters.engineRunning ? "running" : "stopped",
                            tint: counters.engineRunning ? Design.Palette.positive : .orange)
                        row("Buffer", "\(counters.bufferedFrames) frames · \(String(format: "%.0f", counters.latencyMilliseconds)) ms")
                        row("Produced", "\(counters.produced) frames total")
                        row("Consumed", "\(counters.consumed) frames total")
                        row("Volume", String(format: "%.0f%% · %@",
                                             store.global.emulation.volume * 100,
                                             store.global.emulation.isMuted ? "muted" : "unmuted"))
                    }

                    SettingsCard("Throughput") {
                        row("Callbacks", String(format: "%.1f/s · %llu total", rates.callbacks, callbacksTotal),
                            tint: rates.callbacks > 0 ? Design.Palette.ink : .orange)
                        row("Produced/s", String(format: "%.0f frames", rates.produced))
                        row("Consumed/s", String(format: "%.0f frames", rates.consumed))
                        row("Underruns", "\(counters.underruns)",
                            tint: counters.underruns > 0 ? .orange : Design.Palette.ink)
                        row("Dropped", "\(counters.dropped)",
                            tint: counters.dropped > 0 ? .orange : Design.Palette.ink)
                    }

                    SettingsCard("Touch") {
                        row("Taps", "\(touch.taps)",
                            tint: touch.taps > 0 ? Design.Palette.ink : .orange)
                        row("Polls", "\(touch.polls)",
                            tint: touch.polls > 0 ? Design.Palette.ink : .orange)
                        row("Pressed frames", "\(touch.pressedFrames)",
                            tint: touch.pressedFrames >= 2 ? Design.Palette.positive : .orange)
                        hint("Tap the lower screen once and read the deltas: Taps +1, Polls above zero, Pressed frames +2 or more. Taps staying put means the tap never reached the emulator, and Pressed frames staying put while Polls climbs means the press is not being read as one.")
                    }

                    SettingsCard("How to read this") {
                        hint("Callbacks at 0/s means the core is not asking us for audio at all — nothing below that point can be the problem.")
                        hint("Produced/s should sit near the core rate. If it is near zero while callbacks are healthy, the core is sending silence.")
                        hint("Consumed/s should roughly match produced/s. Consumed near zero with audio playing means the render thread is not being pulled.")
                        hint("Underruns climbing means the buffer is too small for the emulator's timing; drops mean it is being outrun.")
                        hint("A refused graph is listed above with the exception name, and written to Documents/Azahar/log/frontend-crash.log.")
                    }
                }
                .padding(.horizontal, Theme.sideMargin)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
        }
        .onAppear(perform: sample)
        .onReceive(timer) { _ in sample() }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Audio diagnostics")
                    .font(Theme.title)
                    .foregroundColor(Theme.primaryInk)
                Text("Live from the audio thread and the touch path, twice a second")
                    .font(Theme.subtitle)
                    .foregroundColor(Theme.secondaryInk)
            }
            Spacer(minLength: 12)
            Button(action: { presentationMode.wrappedValue.dismiss() }) {
                Text("Done")
                    .font(Theme.chipFont)
                    .foregroundColor(Theme.primaryInk)
                    .padding(.horizontal, 16)
                    .chipSurface(height: 36)
            }
            .buttonStyle(CardButtonStyle(scale: 0.96))
        }
    }

    private var failureCard: some View {
        SettingsCard("Audio unavailable") {
            Text(counters.failureName ?? "NSException")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.orange)
            Text(counters.failureReason ?? "No reason was given.")
                .font(.system(size: 12))
                .foregroundColor(Design.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let frames = counters.failureFrames, !frames.isEmpty {
                Text(frames)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Design.Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Audio stays off and the emulator keeps running. The same text is in Documents/Azahar/log/frontend-crash.log.")
                .font(.system(size: 11))
                .foregroundColor(Design.Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ label: String, _ value: String, tint: Color = Design.Palette.ink) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Design.Palette.secondaryInk)
                .frame(width: 104, alignment: .leading)
            Text(value)
                .font(Theme.monospacedSmall)
                .foregroundColor(tint)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(Design.Palette.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Sampling

    private func sample() {
        let now = Date()
        let snapshot = AudioOutput.shared.snapshot()
        counters = snapshot
        callbacksTotal = AZCoreAudioBatchCalls()

        var polls: UInt64 = 0
        var pressedFrames: UInt64 = 0
        AZCorePointerStats(&polls, &pressedFrames)
        touch = TouchCounters(taps: TouchSurfaceView.taps,
                              polls: polls,
                              pressedFrames: pressedFrames)

        let audioSession = AVAudioSession.sharedInstance()
        var info = SessionInfo()
        info.category = audioSession.category.rawValue
        info.hardwareRate = audioSession.sampleRate
        if let output = audioSession.currentRoute.outputs.first {
            info.channels = output.channels?.count ?? 0
            let type = output.portType.rawValue.replacingOccurrences(of: "AVAudioSessionPort", with: "")
            info.route = output.portName.isEmpty ? type : "\(output.portName) · \(type)"
        }
        sessionInfo = info

        if let base = baseline {
            let elapsed = max(now.timeIntervalSince(base.time), 0.1)
            var measured = Rates()
            measured.callbacks = Double(callbacksTotal &- base.callbacks) / elapsed
            measured.produced = Double(snapshot.produced &- base.produced) / elapsed
            measured.consumed = Double(snapshot.consumed &- base.consumed) / elapsed
            rates = measured
        }

        baseline = Baseline(callbacks: callbacksTotal,
                            produced: snapshot.produced,
                            consumed: snapshot.consumed,
                            time: now)
    }
}
