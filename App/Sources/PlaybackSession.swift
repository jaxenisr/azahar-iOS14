import Foundation
import CoreGraphics
import QuartzCore

/// Runs one emulation session.
///
/// The core is single threaded from the frontend's point of view: it is
/// initialised, loaded, run and unloaded on the thread this type starts, and its
/// frame callback arrives on that same thread. Frames and measurements are
/// published to the main thread, where SwiftUI draws them.
final class PlaybackSession: ObservableObject, Identifiable {
    enum Phase: Equatable {
        /// Starting up or running; the screen shows the last frame it got.
        case running
        /// The core refused the content or failed to start. The string is what the
        /// core itself said, not a paraphrase.
        case failed(String)
        case finished
    }

    /// libretro RETRO_DEVICE_ID_JOYPAD_* ids; bit position equals the id.
    enum Pad {
        static let b: UInt32 = 1 << 0
        static let y: UInt32 = 1 << 1
        static let select: UInt32 = 1 << 2
        static let start: UInt32 = 1 << 3
        static let up: UInt32 = 1 << 4
        static let down: UInt32 = 1 << 5
        static let left: UInt32 = 1 << 6
        static let right: UInt32 = 1 << 7
        static let a: UInt32 = 1 << 8
        static let x: UInt32 = 1 << 9
        static let l: UInt32 = 1 << 10
        static let r: UInt32 = 1 << 11
    }

    let id = UUID()
    let game: GameEntry
    let resolutionScale: Int

    @Published private(set) var phase: Phase = .running
    @Published private(set) var image: CGImage?
    @Published private(set) var framesPerSecond: Double = 0
    @Published private(set) var speedPercent: Double = 0
    @Published private(set) var frameMilliseconds: Double = 0
    @Published private(set) var deliveredFrames: UInt64 = 0
    @Published private(set) var coreMessage: String?
    @Published private(set) var rendererName = "starting"
    @Published private(set) var usesHardwareVideo = false

    private let coreDirectory: URL
    private var thread: Thread?
    private var buttons: UInt32 = 0
    private var wantsToRun = false

    private let latestLock = NSLock()
    private var latestImage: CGImage?
    private var deliveryPending = false

    init(game: GameEntry, coreDirectory: URL, resolutionScale: Int = 1) {
        self.game = game
        self.coreDirectory = coreDirectory
        self.resolutionScale = min(max(resolutionScale, 1), 4)
    }

    /// The Metal layer the Vulkan renderer presents into. It has to exist before
    /// the core is loaded, because the core asks for a device during load.
    func attach(metalLayer: CAMetalLayer) {
        AZCoreSetMetalLayer(Unmanaged.passUnretained(metalLayer).toOpaque())
    }

    func startIfNeeded() {
        guard !wantsToRun else { return }
        wantsToRun = true
        let thread = Thread { [weak self] in
            self?.run()
        }
        thread.name = "azahar.playback"
        thread.qualityOfService = .userInteractive
        thread.stackSize = 8 << 20
        self.thread = thread
        thread.start()
    }

    /// Asks the thread to stop. Teardown happens on that thread, so no core call
    /// ever runs concurrently with another.
    func stop() {
        wantsToRun = false
    }

    // MARK: - Input

    func setButton(_ mask: UInt32, pressed: Bool) {
        if pressed {
            buttons |= mask
        } else {
            buttons &= ~mask
        }
        AZCoreSetButtons(buttons)
    }

    func setCirclePad(x: Int, y: Int) {
        AZCoreSetCirclePad(Int32(x), Int32(y))
    }

    // MARK: - Frame delivery

    fileprivate func publishFrame(_ image: CGImage) {
        latestLock.lock()
        latestImage = image
        let alreadyPending = deliveryPending
        deliveryPending = true
        latestLock.unlock()

        guard !alreadyPending else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.latestLock.lock()
            let frame = self.latestImage
            self.latestImage = nil
            self.deliveryPending = false
            self.latestLock.unlock()
            if let frame = frame {
                self.image = frame
            }
        }
    }

    fileprivate func publishMessage(_ message: String) {
        publish { $0.coreMessage = message }
    }

    fileprivate func publish(_ body: @escaping (PlaybackSession) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            body(self)
        }
    }

    // MARK: - Emulation thread

    private func run() {
        // Ask for the hardware renderer. The bridge only falls back to the core's
        // software path when a stage of Vulkan setup fails, and it keeps the reason,
        // which the overlay then shows.
        AZCoreSetRendererPreference(true)
        AZCoreSetOption("citra_graphics_api", "Vulkan")
        AZCoreSetOption("graphics_api", "Vulkan")
        AZCoreSetOption("citra_resolution_factor", "\(resolutionScale)")
        AZCoreSetOption("resolution_factor", "\(resolutionScale)")

        guard AZCoreInitialize(coreDirectory.path, coreDirectory.path) else {
            fail(AZCoreLastError() ?? "the core failed to initialise")
            return
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        AZCoreSetFrameCallback(playbackFrameCallback, context)
        AZCoreSetMessageCallback(playbackMessageCallback, context)

        let loaded = AZCoreLoadGame(game.url.path)
        if !loaded {
            let reason = AZCoreLastError() ?? "the core refused to load this file"
            AZCoreSetFrameCallback(nil, nil)
            AZCoreSetMessageCallback(nil, nil)
            AZCoreShutdown()
            fail(reason)
            return
        }

        let renderer = String(cString: AZCoreRendererName())
        let hardware = AZCoreUsesHardwareVideo()
        publish { session in
            session.rendererName = renderer
            session.usesHardwareVideo = hardware
        }

        if let message = AZCoreLastMessage() {
            publishMessage(message)
        }

        var targetInterval = 1.0 / max(AZCoreFrameRate(), 1.0)
        var reportStart = CACurrentMediaTime()
        var framesAtReport = AZCoreFramesDelivered()
        var emulatedSeconds = 0.0

        while wantsToRun {
            let frameStart = CACurrentMediaTime()
            AZCoreRunFrame()
            let frameEnd = CACurrentMediaTime()
            emulatedSeconds += frameEnd - frameStart

            let elapsed = frameEnd - reportStart
            if elapsed >= 0.5 {
                let delivered = AZCoreFramesDelivered()
                let frames = Double(delivered &- framesAtReport)
                let measuredFps = frames / elapsed
                let emulatedMs = frames > 0 ? (emulatedSeconds / frames) * 1000 : 0
                // How fast the emulator runs relative to the 3DS's own frame rate.
                let speed = emulatedMs > 0 ? (targetInterval * 1000 / emulatedMs) * 100 : 0
                let name = String(cString: AZCoreRendererName())

                publish { session in
                    session.framesPerSecond = measuredFps
                    session.speedPercent = speed
                    session.frameMilliseconds = emulatedMs
                    session.deliveredFrames = delivered
                    session.rendererName = name
                }

                if let message = AZCoreLastMessage() {
                    publishMessage(message)
                }

                framesAtReport = delivered
                emulatedSeconds = 0
                reportStart = frameEnd
                // Content can change its frame rate after loading.
                targetInterval = 1.0 / max(AZCoreFrameRate(), 1.0)
            }

            let remaining = targetInterval - (CACurrentMediaTime() - frameStart)
            if remaining > 0.001 {
                Thread.sleep(forTimeInterval: remaining)
            }
        }

        AZCoreUnloadGame()
        AZCoreSetFrameCallback(nil, nil)
        AZCoreSetMessageCallback(nil, nil)
        AZCoreShutdown()

        publish { $0.phase = .finished }
    }

    private func fail(_ reason: String) {
        publish { $0.phase = .failed(reason) }
    }
}

// Callbacks handed to the core must be plain C functions, so the session travels
// as an opaque pointer instead of a capture.

private func session(from context: UnsafeMutableRawPointer?) -> PlaybackSession? {
    guard let context = context else { return nil }
    return Unmanaged<PlaybackSession>.fromOpaque(context).takeUnretainedValue()
}

private let playbackFrameCallback: AZCoreFrameCallback = { image, context in
    guard let image = image, let session = session(from: context) else { return }
    session.publishFrame(image)
}

private let playbackMessageCallback: AZCoreMessageCallback = { message, context in
    guard let message = message, let session = session(from: context) else { return }
    session.publishMessage(String(cString: message))
}
