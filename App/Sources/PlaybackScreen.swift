import SwiftUI
import UIKit

/// Full screen emulation. The core draws into a bitmap; this view hands that
/// bitmap straight to a layer and keeps the numbers visible.
struct PlaybackScreen: View {
    @ObservedObject var session: PlaybackSession
    @Environment(\.presentationMode) private var presentationMode
    @State private var showsOverlay = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
            if showsOverlay {
                overlay
            }
            controls
        }
        .statusBar(hidden: true)
        .onAppear { session.startIfNeeded() }
        .onDisappear { session.stop() }
    }

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .failed(let reason):
            failure(reason)
        case .running, .finished:
            if let image = session.image {
                FrameImageView(image: image)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Text("Starting \(session.game.title)")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
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
        VStack {
            HStack(alignment: .top) {
                statistics
                Spacer()
                Button(action: { presentationMode.wrappedValue.dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }
                .accessibilityLabel("Stop emulation")
            }
            Spacer()
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
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private var statistics: some View {
        VStack(alignment: .leading, spacing: 3) {
            statistic("FPS", String(format: "%.1f", session.framesPerSecond))
            statistic("Speed", String(format: "%.1f%% of real time", session.speedPercent))
            statistic("Frame", String(format: "%.1f ms", session.frameMilliseconds))
            statistic("Renderer", session.rendererName)
            statistic("Frames", "\(session.deliveredFrames)")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.6)))
    }

    private func statistic(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .foregroundColor(.green.opacity(0.7))
                .frame(width: 62, alignment: .leading)
            Text(value)
                .foregroundColor(.green)
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
    }

    // MARK: - Controls

    private var controls: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                dpad
                Spacer()
                HStack(spacing: 12) {
                    VStack(spacing: 8) {
                        PadButton(label: "X", mask: PlaybackSession.Pad.x, session: session)
                        PadButton(label: "Y", mask: PlaybackSession.Pad.y, session: session)
                    }
                    VStack(spacing: 8) {
                        PadButton(label: "B", mask: PlaybackSession.Pad.b, session: session)
                        PadButton(label: "A", mask: PlaybackSession.Pad.a, session: session)
                    }
                }
                Spacer()
                VStack(spacing: 8) {
                    PadButton(label: "Start", mask: PlaybackSession.Pad.start, session: session)
                    PadButton(label: "Select", mask: PlaybackSession.Pad.select, session: session)
                    Button(action: { showsOverlay.toggle() }) {
                        Text("HUD")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.75))
                            .frame(width: 58, height: 30)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 26)
        }
    }

    private var dpad: some View {
        VStack(spacing: 8) {
            PadButton(label: "▲", mask: PlaybackSession.Pad.up, session: session)
            HStack(spacing: 8) {
                PadButton(label: "◀", mask: PlaybackSession.Pad.left, session: session)
                PadButton(label: "▼", mask: PlaybackSession.Pad.down, session: session)
                PadButton(label: "▶", mask: PlaybackSession.Pad.right, session: session)
            }
        }
    }
}

private struct PadButton: View {
    let label: String
    let mask: UInt32
    let session: PlaybackSession
    @State private var isPressed = false

    var body: some View {
        Text(label)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white.opacity(0.9))
            .frame(width: 52, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(isPressed ? 0.32 : 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressed else { return }
                        isPressed = true
                        session.setButton(mask, pressed: true)
                    }
                    .onEnded { _ in
                        isPressed = false
                        session.setButton(mask, pressed: false)
                    }
            )
    }
}

/// Draws the core's most recent frame. A layer's contents is the cheapest path
/// from a CGImage to the screen; no per-frame texture upload is needed.
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
        super.init(coder: coder)
        backgroundColor = .black
        layer.contentsGravity = .resizeAspect
    }
}
