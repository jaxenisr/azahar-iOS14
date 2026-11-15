import Foundation
import CoreGraphics
import QuartzCore
import Darwin

/// What the audio path is doing, as the overlay reports it.
struct AudioStats: Equatable {
    var state = "idle"
    var batchCallbacksPerSecond: Double = 0
    var producedPerSecond: Double = 0
    var consumedPerSecond: Double = 0
    var bufferedMilliseconds: Double = 0
    var underruns: UInt64 = 0
    var dropped: UInt64 = 0
    var coreSampleRate: Double = 0
    var engineRunning = false
}

/// Runs one emulation session.
///
/// The core is single threaded from the frontend's point of view: it is
/// initialised, loaded, run and unloaded on the thread this type starts, and its
/// frame and audio callbacks arrive on that same thread. Frames, audio figures
/// and measurements are published to the main thread, where SwiftUI draws them.
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
    let settings: EmulationSettings
    let coreDirectory: URL

    @Published private(set) var phase: Phase = .running
    @Published private(set) var image: CGImage?
    @Published private(set) var framesPerSecond: Double = 0
    @Published private(set) var targetFramesPerSecond: Double = 0
    @Published private(set) var speedPercent: Double = 0
    @Published private(set) var frameMilliseconds: Double = 0
    @Published private(set) var deliveredFrames: UInt64 = 0
    @Published private(set) var coreMessage: String?
    @Published private(set) var rendererName = "starting"
    @Published private(set) var usesHardwareVideo = false
    @Published private(set) var audio = AudioStats()
    @Published private(set) var saveStateMessage: String?
    @Published private(set) var isLoaded = false

    var resolutionScale: Int { settings.clampedResolution }
    var layout: PlaybackLayout { settings.layout }
    var speedLimitTitle: String { settings.speed.title }

   /// Directory holding this title's one save-state slot.
    var stateDirectory: URL {
        coreDirectory.appendingPathComponent("savestates", isDirectory: true)
    }

    var stateURL: URL {
        stateDirectory.appendingPathComponent("\(game.id).state")
    }

    private var thread: Thread?
    private var buttons: UInt32 = 0
    private var wantsToRun = false

    private let latestLock = NSLock()
    private var latestImage: CGImage?
    private var deliveryPending = false

    private let stateLock = NSLock()
    private var pendingStateAction: StateAction?

    private enum StateAction {
        case save
        case load
    }

    init(game: GameEntry, coreDirectory: URL, settings: EmulationSettings) {
        self.game = game
        self.coreDirectory = coreDirectory
        self.settings = settings
    }

    /// The pre-settings call site: resolution and layout only, everything else at
    /// its default until the settings screen exists.
    convenience init(game: GameEntry,
                     coreDirectory: URL,
                     resolutionScale: Int = 1,
                     layout: PlaybackLayout = .largeScreen) {
        var settings = EmulationSettings()
        settings.resolutionScale = resolutionScale
        settings.layout = layout
        self.init(game: game, coreDirectory: coreDirectory, settings: settings)
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

    func setButtons(_ mask: UInt32) {
        buttons = mask
        AZCoreSetButtons(buttons)
    }

    func setCirclePad(x: Int, y: Int) {
        let clampedX = min(max(x, -32767), 32767)
        let clampedY = min(max(y, -32767), 32767)
        AZCoreSetCirclePad(Int32(clampedX), Int32(clampedY))
    }

    /// Touch position in frame coordinates: -1 is the left/top edge of the frame
    /// the core produces, 1 the right/bottom edge. The core maps this onto the
    /// bottom screen of whichever layout is active.
    func setPointer(x: CGFloat, y: CGFloat, pressed: Bool) {
        AZCoreSetPointer(Float(x), Float(y), pressed)
    }

    func releasePointer() {
        AZCoreSetPointer(0, 0, false)
    }

    // MARK: - Save states

    func saveState() {
        requestState(.save)
    }

    func loadState() {
        requestState(.load)
    }

    private func requestState(_ action: StateAction) {
        stateLock.lock()
        pendingStateAction = action
        stateLock.unlock()
    }

    private func takeStateAction() -> StateAction? {
        stateLock.lock()
        defer { stateLock.unlock() }
        let action = pendingStateAction
        pendingStateAction = nil
        return action
    }

    static func stateDescription(for game: GameEntry, coreDirectory: URL) -> String {
        let url = coreDirectory
            .appendingPathComponent("savestates", isDirectory: true)
            .appendingPathComponent("\(game.id).state")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              let date = attributes[.modificationDate] as? Date else {
            return "no state saved yet"
        }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB]
        formatter.countStyle = .file
        let stamp = DateFormatter()
        stamp.dateStyle = .short
        stamp.timeStyle = .short
        return "\(formatter.string(fromByteCount: size.int64Value)) · \(stamp.string(from: date))"
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

    fileprivate func publishStatusMessage(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.saveStateMessage = message
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
                guard let self = self, self.saveStateMessage == message else { return }
                self.saveStateMessage = nil
            }
        }
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
        AZCoreSetOption("citra_resolution_factor", "\(settings.clampedResolution)")
        AZCoreSetOption("resolution_factor", "\(settings.clampedResolution)")
        AZCoreSetOption("citra_layout_option", settings.layout.rawValue)
        AZCoreSetOption("layout_option", settings.layout.rawValue)
        AZCoreSetOption("citra_cpu_clock_percentage", "\(settings.clampedClock)")
        // The core reads touch from the pointer device; there is no mouse here.
        AZCoreSetOption("citra_enable_touch_touchscreen", "enabled")
        AZCoreSetOption("citra_enable_mouse_touchscreen", "disabled")

        AZCoreSetAudioCallback(playbackAudioCallback, nil)

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
            AZCoreSetAudioCallback(nil, nil)
            AZCoreShutdown()
            fail(reason)
            return
        }

        let renderer = String(cString: AZCoreRendererName())
        let hardware = AZCoreUsesHardwareVideo()
        publish { session in
            session.rendererName = renderer
            session.usesHardwareVideo = hardware
            session.isLoaded = true
        }

        if let message = AZCoreLastMessage() {
            publishMessage(message)
        }

        // Audio is started at the rate the core reports, never at an assumed one.
        AudioOutput.shared.setVolume(Float(settings.volume))
        AudioOutput.shared.setMuted(settings.isMuted)
        AudioOutput.shared.start(sampleRate: AZCoreSampleRate())

        var targetFps = max(AZCoreFrameRate(), 1.0)
        var targetInterval = 1.0 / targetFps

        var reportStart = CACurrentMediaTime()
        var framesAtReport: UInt64 = 0
        var delivered: UInt64 = 0
        var emulatedSeconds = 0.0

        var lastBatchCalls = AZCoreAudioBatchCalls()
        var lastProduced: UInt64 = 0
        var lastConsumed: UInt64 = 0

        var nextDeadline = CACurrentMediaTime()

        while wantsToRun {
            let frameStart = CACurrentMediaTime()
            AZCoreRunFrame()
            let frameEnd = CACurrentMediaTime()

            delivered &+= 1
            emulatedSeconds += frameEnd - frameStart

            if let action = takeStateAction() {
                perform(action)
            }

            // Pacing. Deadlines accumulate from the previous deadline rather than
            // from this frame's end, so a sleep that overshoots is paid back by a
            // shorter next sleep instead of dragging the rate down permanently.
            if let multiplier = settings.speed.pacingMultiplier {
                let interval = targetInterval / multiplier
                nextDeadline += interval
                if nextDeadline < frameEnd {
                    nextDeadline = frameEnd
                }
                pace(until: nextDeadline)
            }

            let elapsed = CACurrentMediaTime() - reportStart
            if elapsed >= 0.5 {
                let frames = delivered &- framesAtReport
                let measuredFps = elapsed > 0 ? Double(frames) / elapsed : 0
                let emulatedMs = frames > 0 ? (emulatedSeconds / Double(frames)) * 1000 : 0
                // Speed is how much emulated time the thread produced per second
                // of wall time, not how long retro_run took: the pacing sleep is
                // part of the emulator running at real time.
                let achieved = targetFps > 0 ? (measuredFps / targetFps) * 100 : 0
                let name = String(cString: AZCoreRendererName())
                targetFps = max(AZCoreFrameRate(), 1.0)
                targetInterval = 1.0 / targetFps

                let audioCounters = AudioOutput.shared.snapshot()
                let batchCalls = AZCoreAudioBatchCalls()
                var stats = AudioStats()
                stats.state = audioCounters.state
                stats.engineRunning = audioCounters.engineRunning
                stats.coreSampleRate = audioCounters.coreSampleRate
                stats.bufferedMilliseconds = audioCounters.latencyMilliseconds
                stats.underruns = audioCounters.underruns
                stats.dropped = audioCounters.dropped
                stats.batchCallbacksPerSecond = Double(batchCalls &- lastBatchCalls) / elapsed
                stats.producedPerSecond = Double(audioCounters.produced &- lastProduced) / elapsed
                stats.consumedPerSecond = Double(audioCounters.consumed &- lastConsumed) / elapsed
                lastBatchCalls = batchCalls
                lastProduced = audioCounters.produced
                lastConsumed = audioCounters.consumed

                publish { session in
                    session.framesPerSecond = measuredFps
                    session.targetFramesPerSecond = targetFps
                    session.speedPercent = achieved
                    session.frameMilliseconds = emulatedMs
                    session.deliveredFrames = delivered
                    session.rendererName = name
                    session.audio = stats
                }

                if let message = AZCoreLastMessage() {
                    publishMessage(message)
                }

                framesAtReport = delivered
                emulatedSeconds = 0
                reportStart = reportStart + elapsed
            }
        }

        AZCoreSetAudioCallback(nil, nil)
        AudioOutput.shared.stop()
        AZCoreUnloadGame()
        AZCoreSetFrameCallback(nil, nil)
        AZCoreSetMessageCallback(nil, nil)
        AZCoreShutdown()

        publish { $0.phase = .finished }
    }

    /// Sleeps until the deadline without spinning a core flat. `usleep` may wake
    /// early; the loop simply sleeps the remainder.
    private func pace(until deadline: CFTimeInterval) {
        while true {
            let remaining = deadline - CACurrentMediaTime()
            if remaining <= 0.0002 {
                return
            }
            usleep(useconds_t(remaining * 1_000_000))
        }
    }

    private func perform(_ action: StateAction) {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: stateDirectory,
                                        withIntermediateDirectories: true,
                                        attributes: nil)
        } catch {
            publishStatusMessage("Save folder unavailable: \(error.localizedDescription)")
            return
        }

        let url = stateURL
        switch action {
        case .save:
            guard AZCoreSaveState(url.path) else {
                publishStatusMessage(AZCoreLastError() ?? "The core could not save a state")
                return
            }
            publishStatusMessage("State saved · \(PlaybackSession.stateDescription(for: game, coreDirectory: coreDirectory))")
        case .load:
            guard manager.fileExists(atPath: url.path) else {
                publishStatusMessage("No save state for this title yet")
                return
            }
            guard AZCoreLoadState(url.path) else {
                publishStatusMessage(AZCoreLastError() ?? "The core could not restore this state")
                return
            }
            publishStatusMessage("State loaded")
        }
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

private let playbackAudioCallback: AZCoreAudioCallback = { frames, frameCount, _ in
    guard let frames = frames, frameCount > 0 else { return }
    AudioOutput.shared.write(frames, frameCount: Int(frameCount))
}
