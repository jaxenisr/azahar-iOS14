import SwiftUI
import UIKit
import QuartzCore

/// Full screen emulation. Vulkan draws into a Metal layer; when the core falls
/// back to its software rasteriser its frames arrive as bitmaps instead. Both
/// paths share the same overlay so the numbers can always be read.
///
/// The game image is never underneath a control: the controls are laid out in the
/// margins the aspect-fit image leaves, and only their own frames take touches.
struct PlaybackScreen: View {
    @ObservedObject var session: PlaybackSession
    @ObservedObject private var store = SettingsStore.shared
    @ObservedObject private var controllers = ControllerMonitor.shared
    @Environment(\.presentationMode) private var presentationMode
    @State private var showsOverlay = true

    private var settings: EmulationSettings { store.global.emulation }

    /// The screen ignores the safe area, so the geometry reader reports none. The
    /// window still knows where the home indicator and the rounded corners are.
    private var safeInsets: UIEdgeInsets {
        let window = UIApplication.shared.windows.first { $0.isKeyWindow }
        return window?.safeAreaInsets ?? .zero
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = ControlMetrics.make(in: geometry.size,
                                              safeArea: safeInsets,
                                              scale: CGFloat(settings.clampedScale))
            ZStack {
                Color.black

                surface
                    .frame(width: metrics.game.width, height: metrics.game.height)
                    .position(x: metrics.game.midX, y: metrics.game.midY)

                TouchSurface { x, y, pressed in
                    session.setPointer(x: x, y: y, pressed: pressed)
                }
                .frame(width: metrics.game.width, height: metrics.game.height)
                .position(x: metrics.game.midX, y: metrics.game.midY)

                if !controllers.isConnected {
                    ControlsOverlay(setup: controlSetup(metrics: metrics, safe: safeInsets),
                                    onButton: { mask, pressed in
                                        session.setButton(mask, pressed: pressed)
                                    },
                                    onStick: { x, y in
                                        session.setCirclePad(x: Int(x * 32767), y: Int(y * 32767))
                                    })
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }

                if case .failed(let reason) = session.phase {
                    failure(reason)
                } else if session.image == nil && !session.usesHardwareVideo {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }

                if showsOverlay {
                    overlay
                } else {
                    hudChip.padding(12)
                        .frame(width: geometry.size.width, height: geometry.size.height,
                               alignment: .topTrailing)
                }
            }
            .statusBar(hidden: true)
        }
        .ignoresSafeArea()
        .background(Color.black)
        .onAppear {
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
    }

    private func controlSetup(metrics: ControlMetrics,
                              safe: UIEdgeInsets) -> OnScreenControlsView.Setup {
        var setup = OnScreenControlsView.Setup()
        setup.opacity = CGFloat(settings.clampedOpacity)
        setup.scale = CGFloat(settings.clampedScale)
        setup.haptics = settings.hapticsEnabled
        setup.landscape = metrics.landscape
        setup.game = metrics.game
        setup.safeArea = safe
        return setup
    }

    private var surface: some View {
        ZStack {
            MetalSurfaceView { layer in
                session.attach(metalLayer: layer)
            }
            if !session.usesHardwareVideo, let image = session.image {
                FrameImageView(image: image)
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

    // MARK: - Overlay

    private var overlay: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                statistics
                Spacer(minLength: 12)
                VStack(spacing: 8) {
                    Button(action: { presentationMode.wrappedValue.dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
                    .accessibilityLabel("Stop emulation")

                    hudChip
                }
            }

            Spacer(minLength: 0)

            if let message = session.saveStateMessage {
                Text(message)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.72)))
                    .padding(.bottom, 10)
            }
            if let message = session.coreMessage {
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.7)))
                    .padding(.horizontal, 24)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var hudChip: some View {
        Button(action: { showsOverlay.toggle() }) {
            Text("HUD")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.green.opacity(0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.5)))
        }
        .accessibilityLabel(showsOverlay ? "Hide diagnostics" : "Show diagnostics")
    }

    private var statistics: some View {
        VStack(alignment: .leading, spacing: 3) {
            statistic("FPS", String(format: "%.1f", session.framesPerSecond))
            statistic("Target", String(format: "%.1f fps", session.targetFramesPerSecond))
            statistic("Speed", String(format: "%.1f%% of real time", session.speedPercent))
            statistic("Limit", session.speedLimitTitle)
            statistic("Frame", String(format: "%.1f ms", session.frameMilliseconds))
            statistic("Renderer", session.rendererName)
            statistic("Resolution", "\(session.resolutionScale)x · \(session.layout.title)")
            statistic("Frames", "\(session.deliveredFrames)")

            Divider().background(Color.green.opacity(0.25)).padding(.vertical, 2)

            statistic("Audio", session.audio.state)
            statistic("Audio cbs", String(format: "%.1f/s · batch", session.audio.batchCallbacksPerSecond))
            statistic("Audio made", String(format: "%.0f/s · %.0f Hz", session.audio.producedPerSecond, session.audio.coreSampleRate))
            statistic("Audio used", String(format: "%.0f/s", session.audio.consumedPerSecond))
            statistic("Audio buf", String(format: "%.0f ms · %llu under · %llu drop",
                                         session.audio.bufferedMilliseconds,
                                         session.audio.underruns,
                                         session.audio.dropped))

            HStack(spacing: 6) {
                statisticButton("Save state") { session.saveState() }
                statisticButton("Load state") { session.loadState() }
            }
            .padding(.top, 4)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.62)))
    }

    private func statistic(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .foregroundColor(.green.opacity(0.7))
                .frame(width: 78, alignment: .leading)
            Text(value)
                .foregroundColor(.green)
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
    }

    private func statisticButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.green.opacity(0.16)))
        }
    }
}

/// A UIView backed by a CAMetalLayer, which is what MoltenVK presents into.
struct MetalSurfaceView: UIViewRepresentable {
    let onLayer: (CAMetalLayer) -> Void

    func makeUIView(context: Context) -> MetalContainerView {
        let view = MetalContainerView()
        if let layer = view.layer as? CAMetalLayer {
            onLayer(layer)
        }
        return view
    }

    func updateUIView(_ view: MetalContainerView, context: Context) {}
}

final class MetalContainerView: UIView {
    override class var layerClass: AnyClass {
        CAMetalLayer.self
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isUserInteractionEnabled = false
        if let layer = layer as? CAMetalLayer {
            layer.framebufferOnly = false
            layer.isOpaque = true
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Draws a software-rendered frame. A layer's contents is the cheapest path from
/// a CGImage to the screen.
struct FrameImageView: UIViewRepresentable {
    let image: CGImage

    func makeUIView(context: Context) -> FrameContainerView {
        FrameContainerView()
    }

    func updateUIView(_ view: FrameContainerView, context: Context) {
        view.layer.contents = image
    }
}

final class FrameContainerView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        layer.contentsGravity = .resizeAspect
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .nearest
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// The bottom screen is a touchscreen. The core maps a normalised pointer onto the
/// bottom screen itself, so this only has to say where the finger is inside the
/// frame the core is producing.
struct TouchSurface: UIViewRepresentable {
    let onTouch: (CGFloat, CGFloat, Bool) -> Void

    func makeUIView(context: Context) -> TouchSurfaceView {
        let view = TouchSurfaceView()
        view.onTouch = onTouch
        return view
    }

    func updateUIView(_ view: TouchSurfaceView, context: Context) {
        view.onTouch = onTouch
    }
}

final class TouchSurfaceView: UIView {
    var onTouch: ((CGFloat, CGFloat, Bool) -> Void)?
    private var activeTouch: UITouch?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        activeTouch = touch
        report(touch, pressed: true)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        report(touch, pressed: true)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches)
    }

    private func finish(_ touches: Set<UITouch>) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        activeTouch = nil
        onTouch?(0, 0, false)
    }

    /// The frame is letterboxed inside this view exactly as the present path
    /// letterboxes it inside the drawable, so the mapping is the same maths.
    private func report(_ touch: UITouch, pressed: Bool) {
        let point = touch.location(in: self)
        let size = bounds.size
        guard size.width > 1, size.height > 1 else { return }

        let source = AZCoreSourceSize()
        let sourceWidth = source.width > 1 ? source.width : 400
        let sourceHeight = source.height > 1 ? source.height : 480
        let scale = min(size.width / sourceWidth, size.height / sourceHeight)
        guard scale > 0 else { return }

        let drawnWidth = sourceWidth * scale
        let drawnHeight = sourceHeight * scale
        let originX = (size.width - drawnWidth) / 2
        let originY = (size.height - drawnHeight) / 2

        let x = ((point.x - originX) / drawnWidth) * 2 - 1
        let y = ((point.y - originY) / drawnHeight) * 2 - 1
        onTouch?(x, y, pressed)
    }
}
