import AVFoundation
import UIKit

/// One stereo ring buffer between Azahar's emulation thread and CoreAudio's
/// render thread.
///
/// The core produces 32728 Hz stereo pairs in bursts (one per `retro_run`), and
/// CoreAudio asks for 48 kHz blocks at its own pace. The buffer absorbs the
/// difference; if the emulator falls behind, the consumer gets silence (counted
/// as an underrun) rather than stale audio, and if the emulator sprints ahead
/// the oldest frames are dropped so latency never grows without bound.
final class AudioRingBuffer {
    struct Snapshot {
        var produced: UInt64 = 0
        var consumed: UInt64 = 0
        var buffered: Int = 0
        var underruns: UInt64 = 0
        var dropped: UInt64 = 0
    }

    private let capacity: Int
    private var storage: UnsafeMutablePointer<Int16>
    private var writeIndex = 0
    private var readIndex = 0
    private var buffered = 0
    private var produced: UInt64 = 0
    private var consumed: UInt64 = 0
    private var underruns: UInt64 = 0
    private var dropped: UInt64 = 0
    private let lock = NSLock()

    init(capacityFrames: Int) {
        capacity = max(capacityFrames, 1024)
        storage = UnsafeMutablePointer<Int16>.allocate(capacity: capacity * 2)
        storage.initialize(repeating: 0, count: capacity * 2)
    }

    deinit {
        storage.deallocate()
    }

    /// Emulation thread. Copies interleaved stereo frames, dropping the oldest
    /// audio when the producer gets ahead of the consumer.
    func write(_ source: UnsafePointer<Int16>, frameCount: Int) {
        guard frameCount > 0 else { return }

        var frames = frameCount
        var input = source
        if frames > capacity {
            input = source.advanced(by: (frames - capacity) * 2)
            dropped &+= UInt64(frames - capacity)
            frames = capacity
        }

        lock.lock()
        if buffered + frames > capacity {
            let overflow = buffered + frames - capacity
            readIndex = (readIndex + overflow) % capacity
            buffered -= overflow
            dropped &+= UInt64(overflow)
        }

        let first = min(frames, capacity - writeIndex)
        memcpy(storage.advanced(by: writeIndex * 2),
               input,
               first * 2 * MemoryLayout<Int16>.size)
        if frames > first {
            memcpy(storage,
                   input.advanced(by: first * 2),
                   (frames - first) * 2 * MemoryLayout<Int16>.size)
        }
        writeIndex = (writeIndex + frames) % capacity
        buffered += frames
        produced &+= UInt64(frames)
        lock.unlock()
    }

    /// Audio render thread. Returns how many frames were available; the caller
    /// fills the remainder with silence.
    func read(into destination: UnsafeMutablePointer<Int16>, frameCount: Int) -> Int {
        guard frameCount > 0 else { return 0 }

        lock.lock()
        let frames = min(frameCount, buffered)
        if frames > 0 {
            let first = min(frames, capacity - readIndex)
            memcpy(destination,
                   storage.advanced(by: readIndex * 2),
                   first * 2 * MemoryLayout<Int16>.size)
            if frames > first {
                memcpy(destination.advanced(by: first * 2),
                       storage,
                       (frames - first) * 2 * MemoryLayout<Int16>.size)
            }
            readIndex = (readIndex + frames) % capacity
            buffered -= frames
            consumed &+= UInt64(frames)
        }
        if frames < frameCount {
            underruns &+= 1
        }
        lock.unlock()
        return frames
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        var result = Snapshot()
        result.produced = produced
        result.consumed = consumed
        result.buffered = buffered
        result.underruns = underruns
        result.dropped = dropped
        return result
    }
}

/// Plays whatever the core produces.
///
/// One `AVAudioSourceNode` pulls from the ring buffer in the core's own sample
/// rate and the engine's mixer converts to the hardware rate, so nothing here
/// assumes 44.1 or 48 kHz: if Azahar ever changes its rate, the pitch stays
/// right. The audio session is a `.playback` session, which is what makes an
/// emulator audible with the ring/silent switch on, and it is reactivated after
/// calls, Siri, route changes and a trip to the background.
final class AudioOutput {
    struct Counters {
        var produced: UInt64 = 0
        var consumed: UInt64 = 0
        var bufferedFrames: Int = 0
        var underruns: UInt64 = 0
        var dropped: UInt64 = 0
        var coreSampleRate: Double = 0
        var latencyMilliseconds: Double = 0
        var engineRunning = false
        var state = "idle"
        var lastError: String?
    }

    static let shared = AudioOutput()

    private let ring = AudioRingBuffer(capacityFrames: 16384)
    private var engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private let scratchFrames = 8192
    private let scratch: UnsafeMutablePointer<Int16>
    private let lock = NSLock()
    private var running = false
    private var desiredRate: Double = 32728
    private var volume: Float = 1
    private var muted = false
    private var state = "idle"
    private var lastError: String?
    private var observers: [NSObjectProtocol] = []

    private init() {
        scratch = UnsafeMutablePointer<Int16>.allocate(capacity: scratchFrames * 2)
        scratch.initialize(repeating: 0, count: scratchFrames * 2)
        observe()
    }

    // MARK: - Lifecycle

    /// Starts (or restarts) playback at the core's rate. Safe to call twice.
    func start(sampleRate: Double) {
        lock.lock()
        let changedRate = abs(sampleRate - desiredRate) > 0.5
        desiredRate = sampleRate > 1000 ? sampleRate : 32728
        let alreadyRunning = running && engine.isRunning && !changedRate
        lock.unlock()

        activateSession()
        if alreadyRunning { return }
        if changedRate || sourceNode == nil {
            buildEngine()
        } else {
            startEngine()
        }
    }

    func stop() {
        lock.lock()
        running = false
        state = "stopped"
        lock.unlock()
        engine.stop()
        if let node = sourceNode {
            engine.detach(node)
            sourceNode = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false,
                                                      options: .notifyOthersOnDeactivation)
    }

    func setVolume(_ value: Float) {
        lock.lock()
        volume = max(0, min(1, value))
        lock.unlock()
        applyVolume()
    }

    func setMuted(_ muted: Bool) {
        lock.lock()
        self.muted = muted
        lock.unlock()
        applyVolume()
    }

    /// Emulation thread. Called for every `audio_sample_batch`.
    func write(_ frames: UnsafePointer<Int16>, frameCount: Int) {
        ring.write(frames, frameCount: frameCount)
    }

    func snapshot() -> Counters {
        let ringState = ring.snapshot()
        lock.lock()
        let rate = desiredRate
        let runningNow = running
        let note = state
        let error = lastError
        let engineAlive = engine.isRunning
        lock.unlock()

        var counters = Counters()
        counters.produced = ringState.produced
        counters.consumed = ringState.consumed
        counters.bufferedFrames = ringState.buffered
        counters.underruns = ringState.underruns
        counters.dropped = ringState.dropped
        counters.coreSampleRate = rate
        counters.latencyMilliseconds = rate > 0 ? Double(ringState.buffered) / rate * 1000 : 0
        counters.engineRunning = engineAlive
        counters.state = note
        counters.lastError = error

        if runningNow && !engineAlive && error == nil {
            counters.lastError = "engine stopped"
        }
        return counters
    }

    // MARK: - Engine

    private func buildEngine() {
        lock.lock()
        let rate = desiredRate
        lock.unlock()

        engine.stop()
        if let node = sourceNode {
            engine.detach(node)
            sourceNode = nil
        }
        engine = AVAudioEngine()

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: rate,
                                   channels: 2,
                                   interleaved: true)
            ?? AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)

        guard let audioFormat = format else {
            fail("the audio format \(Int(rate)) Hz stereo could not be created")
            return
        }

        let node = AVAudioSourceNode(format: audioFormat) { [weak self] _, _, frameCount, bufferList -> OSStatus in
            guard let self = self else { return noErr }
            return self.render(frameCount: frameCount, into: bufferList)
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: audioFormat)
        sourceNode = node
        applyVolume()
        startEngine()
    }

    private func startEngine() {
        guard sourceNode != nil else {
            buildEngine()
            return
        }
        do {
            try engine.start()
            lock.lock()
            running = true
            lastError = nil
            state = describeSession(prefix: "playing")
            lock.unlock()
        } catch {
            fail("engine start failed: \(error.localizedDescription)")
        }
    }

    private func fail(_ message: String) {
        lock.lock()
        running = false
        lastError = message
        state = "error"
        lock.unlock()
    }

    private func applyVolume() {
        lock.lock()
        let level = muted ? 0 : volume
        lock.unlock()
        guard sourceNode != nil else { return }
        engine.mainMixerNode.outputVolume = level
    }

    private func render(frameCount: AVAudioFrameCount,
                        into bufferList: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let frames = Int(frameCount)
        let list = UnsafeMutableAudioBufferListPointer(bufferList)
        guard let first = list.first, let raw = first.mData else { return noErr }

        let floats = raw.assumingMemoryBound(to: Float.self)
        let wanted = frames * 2
        let read = ring.read(into: scratch, frameCount: min(frames, scratchFrames))
        let available = min(read, scratchFrames)

        var index = 0
        while index < available * 2 {
            floats[index] = Float(scratch[index]) * (1.0 / 32768.0)
            index += 1
        }
        while index < wanted {
            floats[index] = 0
            index += 1
        }
        return noErr
    }

    // MARK: - Session

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            lock.lock()
            if lastError == nil || state == "idle" || state == "stopped" {
                state = describeSession(prefix: "ready")
            }
            lock.unlock()
        } catch {
            fail("session failed: \(error.localizedDescription)")
        }
    }

    private func describeSession(prefix: String) -> String {
        let session = AVAudioSession.sharedInstance()
        let route = session.currentRoute.outputs.first?.portType.rawValue ?? "no output"
        let hardware = session.sampleRate > 0 ? Int(session.sampleRate) : 0
        let coreRate = Int(desiredRate)
        if hardware > 0 && hardware != coreRate {
            return "\(prefix) · \(coreRate) → \(hardware) Hz · \(shortRoute(route))"
        }
        return "\(prefix) · \(coreRate) Hz · \(shortRoute(route))"
    }

    private func shortRoute(_ raw: String) -> String {
        switch raw {
        case "Speaker": return "speaker"
        case "Headphones": return "headphones"
        case "BluetoothA2DPOutput": return "bluetooth"
        case "BluetoothHFP": return "bluetooth hfp"
        case "AirPlay": return "airplay"
        case "No Output": return "no output"
        default: return raw.replacingOccurrences(of: "AVAudioSessionPort", with: "")
        }
    }

    private func observe() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
                                            object: session,
                                            queue: .main) { [weak self] note in
            self?.handleInterruption(note)
        })

        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification,
                                            object: session,
                                            queue: .main) { [weak self] note in
            self?.handleRouteChange(note)
        })

        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                                            object: session,
                                            queue: .main) { [weak self] _ in
            self?.handleMediaServicesReset()
        })

        // Spelled out rather than as .AVAudioEngineConfigurationChange so the
        // name cannot drift with an SDK rename.
        let configurationChange = Notification.Name("AVAudioEngineConfigurationChangeNotification")
        observers.append(center.addObserver(forName: configurationChange,
                                            object: nil,
                                            queue: .main) { [weak self] _ in
            self?.handleConfigurationChange()
        })

        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                            object: nil,
                                            queue: .main) { [weak self] _ in
            self?.resumeIfWanted(reason: "foreground")
        })
    }

    private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }

        switch type {
        case .began:
            engine.pause()
            lock.lock()
            state = "interrupted"
            lock.unlock()
        case .ended:
            let rawOptions = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            if options.contains(.shouldResume) {
                resumeIfWanted(reason: "interruption ended")
            } else {
                lock.lock()
                state = "interrupted · not resuming"
                lock.unlock()
            }
        default:
            break
        }
    }

    private func handleRouteChange(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }

        switch reason {
        case .oldDeviceUnavailable, .newDeviceAvailable, .override:
            // Keep playing: an unplugged headphone should fall back to the
            // speaker, not silence the emulator.
            resumeIfWanted(reason: "route changed")
        default:
            break
        }
    }

    private func handleConfigurationChange() {
        lock.lock()
        let wanted = running
        lock.unlock()
        guard wanted else { return }
        buildEngine()
    }

    private func handleMediaServicesReset() {
        lock.lock()
        let wanted = running
        lock.unlock()
        guard wanted else { return }
        activateSession()
        buildEngine()
    }

    private func resumeIfWanted(reason: String) {
        lock.lock()
        let wanted = running
        lock.unlock()
        guard wanted else { return }

        activateSession()
        if engine.isRunning { return }
        if sourceNode == nil {
            buildEngine()
        } else {
            do {
                try engine.start()
                lock.lock()
                state = describeSession(prefix: reason)
                lock.unlock()
            } catch {
                buildEngine()
            }
        }
    }
}
