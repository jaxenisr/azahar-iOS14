import SwiftUI
import UIKit
import QuartzCore

/// Full screen emulation. Vulkan draws into a Metal layer; when the core falls
/// back to its software rasteriser its frames arrive as bitmaps instead. Both
/// paths share the same overlay so the numbers can always be read.
///
/// Everything on this screen is placed by `PlaybackGeometry`: the picture is
/// centred in the space the controls leave, the controls sit in the margins, and
/// the HUD docks in a margin too. Nothing is drawn over the game.
struct PlaybackScreen: View {
    @ObservedObject var session: PlaybackSession
    @ObservedObject private var store = SettingsStore.shared
    @ObservedObject private var controllers = ControllerMonitor.shared
    @Environment(\.presentationMode) private var presentationMode
    @State private var showsOverlay = true
    @State private var showsDiagnostics = false

    private var settings: EmulationSettings { store.global.emulation }

    /// The screen ignores the safe area, so the geometry reader reports none. The
    /// window still knows where the home indicator and the rounded corners are.
    private var safeInsets: UIEdgeInsets {
        let window = UIApplication.shared.windows.first { $0.isKeyWindow }
        return window?.safeAreaInsets ?? .zero
    }

    /// The core's own geometry, so the picture is drawn at its aspect instead of
    /// being letterboxed inside a rect nobody can see. Stacked is the exception:
    /// the core composes the two screens flush, and the picture as presented has
    /// the hinge in it as well.
    private var sourceAspect: CGFloat {
        if session.layout == .stacked { return PlaybackLayout.stackedAspect }
        let source = AZCoreSourceSize()
        guard source.width > 1, source.height > 1 else { return 400.0 / 480.0 }
        return source.width / source.height
    }

    var body: some View {
        GeometryReader { geometry in
            let hudMetrics = HUDMetrics.make(labels: hudLabels,
                                             widestValues: hudWidestValues,
                                             columns: geometry.size.width > geometry.size.height ? 1 : 2)
            let metrics = PlaybackGeometry.make(in: geometry.size,
                                                safe: safeInsets,
                                                scale: CGFloat(settings.clampedScale),
                                                aspect: sourceAspect,
                                                hud: showsOverlay ? .full : .compact,
                                                hudMetrics: hudMetrics)

            ZStack(alignment: .topLeading) {
                Color.black

                surface
                    .frame(width: metrics.image.width, height: metrics.image.height)
                    .offset(x: metrics.image.minX, y: metrics.image.minY)

                // One hosted view for the touchscreen and the controls. Two of
                // them would put a full screen layer over the picture, and the
                // upper layer takes the touch before the one below is ever asked.
                PlaybackInput(setup: inputSetup(metrics),
                              onTouch: { x, y, pressed in
                                  session.setPointer(x: x, y: y, pressed: pressed)
                              },
                              onButton: { mask, pressed in
                                  session.setButton(mask, pressed: pressed)
                              },
                              onStick: { x, y in
                                  session.setCirclePad(x: Int(x * 32767), y: Int(y * 32767))
                              })
                    .frame(width: geometry.size.width, height: geometry.size.height)

                if case .failed(let reason) = session.phase {
                    failure(reason)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else if session.image == nil && !session.usesHardwareVideo {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        // A spinner must never be able to take a touch from the
                        // surface it is drawn over.
                        .allowsHitTesting(false)
                }

                hud(hudMetrics)
                    .frame(width: metrics.hud.width, height: metrics.hud.height, alignment: .topLeading)
                    .offset(x: metrics.hud.minX, y: metrics.hud.minY)
            }
            .statusBar(hidden: true)
        }
        .ignoresSafeArea()
        .background(Color.black)
        .onAppear {
            // The present path has to know about the hinge before the first frame.
            AZCoreSetStackedPresentation(session.layout == .stacked
                                         ? Float(PlaybackLayout.stackedHinge)
                                         : 0)
            session.startIfNeeded()
            ControllerMonitor.shared.session = session
            ControllerMonitor.shared.refresh()
        }
        .onDisappear {
            session.releasePointer()
            session.stop()
            ControllerMonitor.shared.session = nil
        }
        .onChange(of: settings.volume) { value in
            AudioOutput.shared.setVolume(Float(value))
        }
        .onChange(of: settings.isMuted) { value in
            AudioOutput.shared.setMuted(value)
        }
        .sheet(isPresented: $showsDiagnostics) {
            AudioDiagnosticsView()
        }
    }

    private func inputSetup(_ metrics: PlaybackGeometry) -> PlaybackInputView.Setup {
        var setup = PlaybackInputView.Setup()
        setup.opacity = CGFloat(settings.clampedOpacity)
        setup.image = metrics.image
        setup.stacked = session.layout == .stacked
        setup.hinge = PlaybackLayout.stackedHinge
        setup.showsControls = !controllers.isConnected
        setup.haptics = settings.hapticsEnabled
        setup.button = metrics.button
        setup.offset = metrics.offset
        setup.stick = metrics.stick
        setup.dpad = metrics.dpad
        setup.diamond = metrics.diamond
        setup.shoulderL = metrics.shoulderL
        setup.shoulderR = metrics.shoulderR
        setup.start = metrics.start
        setup.select = metrics.select
        return setup
    }

    private var surface: some View {
        ZStack {
            MetalSurfaceView { layer in
                session.attach(metalLayer: layer)
            }
            if !session.usesHardwareVideo, let image = session.image {
                FrameImageView(image: image,
                               stacked: session.layout == .stacked,
                               hinge: PlaybackLayout.stackedHinge)
            }
        }
        .clipped()
    }


    private func failure(_ reason: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34, weight: .light))
                .foregroundColor(.orange)
            Text("The core would not start this content")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
            Text(reason)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
            Text("The core's own log is in Documents/Azahar/log/frontend.log.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.45))
        }
    }

    // MARK: - HUD

    @ViewBuilder
    private func hud(_ hudMetrics: HUDMetrics) -> some View {
        if showsOverlay {
            hudCard(hudMetrics)
        } else {
            hudPill
        }
    }

    private var hudPill: some View {
        HStack(spacing: 8) {
            Text(String(format: "%.1f", session.framesPerSecond))
                .foregroundColor(.green)
            Text(String(format: "%.1f%%", session.speedPercent))
                .foregroundColor(.green.opacity(0.75))
            hudIcon("chevron.down", label: "Show diagnostics") { showsOverlay = true }
            hudIcon("xmark", label: "Stop emulation") { presentationMode.wrappedValue.dismiss() }
        }
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(Capsule().fill(Color.black.opacity(0.55)))
        .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    private func hudCard(_ hudMetrics: HUDMetrics) -> some View {
        VStack(alignment: .leading, spacing: HUDMetrics.rowSpacing) {
            HStack(spacing: 6) {
                Text(HUDMetrics.heading)
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.7)
                    .foregroundColor(.white.opacity(0.42))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 4)
                hudIcon("chevron.up", label: "Hide diagnostics") { showsOverlay = false }
                hudIcon("xmark", label: "Stop emulation") { presentationMode.wrappedValue.dismiss() }
            }
            .frame(height: HUDMetrics.headerHeight)

            HStack(alignment: .top, spacing: HUDMetrics.columnGap) {
                ForEach(0..<hudMetrics.columns, id: \.self) { column in
                    VStack(alignment: .leading, spacing: HUDMetrics.rowGap) {
                        ForEach(hudMetrics.indices(in: column), id: \.self) { index in
                            statistic(hudRows[index].0, hudRows[index].1, metrics: hudMetrics)
                        }
                    }
                }
            }

            if let failure = audioFailure {
                Text(failure)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.orange)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 5) {
                statisticButton("Save") { session.saveState() }
                statisticButton("Load") { session.loadState() }
                statisticButton("Audio") { showsDiagnostics = true }
            }
            .frame(height: HUDMetrics.buttonsHeight)
        }
        .padding(HUDMetrics.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.62)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1))
        .clipped()
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Rate and Game are two different numbers and two different rows. Rate is
    /// what the emulation thread ran; Game is how many of those frames were a
    /// different picture from the one before. When they disagree, the core is
    /// running but nothing new is reaching the screen.
    private var hudRows: [(String, String)] {
        [
            ("Rate", String(format: "%.1f", session.framesPerSecond)),
            ("Game", String(format: "%.1f", session.gameFramesPerSecond)),
            ("Speed", String(format: "%.1f%%", session.speedPercent)),
            ("Limit", session.speedLimitTitle),
            ("Frame", String(format: "%.1f ms", session.frameMilliseconds)),
            ("Target", String(format: "%.1f", session.targetFramesPerSecond)),
            ("Renderer", rendererToken),
            ("Layout", "\(session.resolutionScale)x \(session.layout.title)"),
            ("Frames", "\(session.deliveredFrames)"),
            ("Audio", audioToken),
            ("Cbs", String(format: "%.0f/s", session.audio.batchCallbacksPerSecond)),
            ("Made", String(format: "%.0f/s", session.audio.producedPerSecond)),
            ("Used", String(format: "%.0f/s", session.audio.consumedPerSecond)),
            ("Buffer", String(format: "%.0f ms", session.audio.bufferedMilliseconds)),
            ("Under", "\(session.audio.underruns)")
        ]
    }

    private var hudLabels: [String] { hudRows.map { $0.0 } }

    /// The widest each value in `hudRows` can get. The card is sized from these
    /// rather than from the numbers on screen, so a value growing a digit does not
    /// resize the card -- and with it the picture -- in the middle of a game.
    private var hudWidestValues: [String] {
        ["60.0", "60.0", "100.0%", "Unlimited", "16.7 ms", "60.0", "Software",
         "4x Side by side", "12345678", "playing", "2400/s", "40000/s", "40000/s",
         "240.0 ms", "9999"]
    }

    /// Which renderer is running, in one word: `rendererName` is either
    /// "Vulkan (MoltenVK): <device>" or the software path with its reason, and the
    /// rest of that string is long enough to push every other row off the card.
    private var rendererToken: String {
        session.rendererName.split(separator: " ").first.map(String.init) ?? "—"
    }

    /// The audio state in one word: "playing · 32728 -> 44100 Hz · speaker" is a
    /// sentence, and the sheet behind the Audio button has all of it.
    private var audioToken: String {
        session.audio.state.split(separator: "·").first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? session.audio.state
    }

    /// Set when the audio graph refused to build. A silent game that says why is
    /// better than a silent game that looks broken.
    private var audioFailure: String? {
        let counters = AudioOutput.shared.snapshot()
        guard !counters.available else { return nil }
        let name = counters.failureName ?? "audio unavailable"
        let reason = counters.failureReason ?? ""
        return "audio off · \(name): \(reason)"
    }

    private func statistic(_ label: String, _ value: String, metrics: HUDMetrics) -> some View {
        HStack(spacing: HUDMetrics.labelGap) {
            Text(label)
                .foregroundColor(.green.opacity(0.6))
                .frame(width: metrics.labelWidth, alignment: .leading)
                .lineLimit(1)
            Text(value)
                .foregroundColor(.green)
                .frame(width: metrics.valueWidth, alignment: .trailing)
                .lineLimit(1)
        }
        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
        .frame(height: HUDMetrics.rowHeight)
    }

    private func hudIcon(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 24, height: 22)
                // A chevron drawn at 10 pt is not a button without this.
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(label)
    }

    private func statisticButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.green)
                .padding(.horizontal, 6)
                .frame(height: 24)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(Color.green.opacity(0.16)))
                .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
    }
}
