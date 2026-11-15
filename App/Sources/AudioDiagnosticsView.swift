import SwiftUI
import AVFoundation

/// The audio path as the device sees it.
///
/// This is the screen to open when there is no sound, because the two questions
/// that matter are answered separately here: is the core producing anything, and
/// is the engine consuming it. When the graph never came up, the exception that
/// stopped it is named, with the reason AVFAudio gave.
struct AudioDiagnosticsView: View {
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject private var store = SettingsStore.shared

    @State private var counters = AudioOutput.Counters()
    @State private var sessionInfo = SessionInfo()
    @State private var rates = Rates()
    @State private var callbacksTotal: UInt64 = 0
    @State private var baseline: Baseline?

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

    private struct Baseline {
        var callbacks: UInt64
        var produced: UInt64
        var consumed: UInt64
        var time: Date
    }

    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.06, blue: 0.08).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if !counters.available {
                        failureCard
                    }

                    SettingsCard("Session") {
                        row("Graph", counters.available ? "built" : "refused",
                            tint: counters.available ? Color.white.opacity(0.85) : .orange)
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
                            tint: counters.engineRunning ? Color.green.opacity(0.85) : .orange)
                        row("Buffer", "\(counters.bufferedFrames) frames · \(String(format: "%.0f", counters.latencyMilliseconds)) ms")
                        row("Produced", "\(counters.produced) frames total")
                        row("Consumed", "\(counters.consumed) frames total")
                        row("Volume", String(format: "%.0f%% · %@",
                                             store.global.emulation.volume * 100,
                                             store.global.emulation.isMuted ? "muted" : "unmuted"))
                    }

                    SettingsCard("Throughput") {
                        row("Callbacks", String(format: "%.1f/s · %llu total", rates.callbacks, callbacksTotal),
                            tint: rates.callbacks > 0 ? Color.white.opacity(0.85) : .orange)
                        row("Produced/s", String(format: "%.0f frames", rates.produced))
                        row("Consumed/s", String(format: "%.0f frames", rates.consumed))
                        row("Underruns", "\(counters.underruns)",
                            tint: counters.underruns > 0 ? .orange : Color.white.opacity(0.85))
                        row("Dropped", "\(counters.dropped)",
                            tint: counters.dropped > 0 ? .orange : Color.white.opacity(0.85))
                    }

                    SettingsCard("How to read this") {
                        hint("Callbacks at 0/s means the core is not asking us for audio at all — nothing below that point can be the problem.")
                        hint("Produced/s should sit near the core rate. If it is near zero while callbacks are healthy, the core is sending silence.")
                        hint("Consumed/s should roughly match produced/s. Consumed near zero with audio playing means the render thread is not being pulled.")
                        hint("Underruns climbing means the buffer is too small for the emulator's timing; drops mean it is being outrun.")
                        hint("A refused graph is listed above with the exception name, and written to Documents/Azahar/log/frontend-crash.log.")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 40)
            }
        }
        .onAppear(perform: sample)
        .onReceive(timer) { _ in sample() }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Audio diagnostics")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                Text("Live from the audio thread, twice a second")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.45))
            }
            Spacer(minLength: 12)
            Button(action: { presentationMode.wrappedValue.dismiss() }) {
                Text("Done")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private var failureCard: some View {
        SettingsCard("Audio unavailable") {
            Text(counters.failureName ?? "NSException")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.orange)
            Text(counters.failureReason ?? "No reason was given.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
            if let frames = counters.failureFrames, !frames.isEmpty {
                Text(frames)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Audio stays off and the emulator keeps running. The same text is in Documents/Azahar/log/frontend-crash.log.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ label: String, _ value: String, tint: Color = Color.white.opacity(0.85)) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.45))
                .frame(width: 104, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(tint)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(.white.opacity(0.45))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Sampling

    private func sample() {
        let now = Date()
        let snapshot = AudioOutput.shared.snapshot()
        counters = snapshot
        callbacksTotal = AZCoreAudioBatchCalls()

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
