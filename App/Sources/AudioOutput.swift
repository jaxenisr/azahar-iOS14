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

/// Plays whatever the core produces, and never takes the emulator down with it.
///
/// One `AVAudioSourceNode` pulls from the ring buffer in the core's own sample
/// rate and the engine's mixer converts to the hardware rate, so nothing here
/// assumes 44.1 or 48 kHz: if Azahar ever changes its rate, the pitch stays
/// right. The audio session is a `.playback` session, which is what makes an
/// emulator audible with the ring/silent switch on, and it is reactivated after
/// calls, Siri, route changes and a trip to the background.
///
/// AVFAudio reports a refused graph as an Objective-C exception, not an error,
/// and an uncaught one aborts the process. Two things follow: the graph is built
/// with the format AVAudioEngine actually supports (deinterleaved float), and
/// every call into AVFoundation runs inside `AZTryCatch`. If one raises anyway,
/// audio is switched off, the name and reason are kept and logged, and the
/// emulator keeps running in silence.
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
        var available = true
        var state = "idle"
        var failureName: String?
        var failureReason: String?
        var failureFrames: String?
    }

    static let shared = AudioOutput()

    private let ring = AudioRingBuffer(capacityFrames: 16384)
    private var engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private let scratchFrames = 8192
    private let scratch: UnsafeMutablePointer<Int16>
    private let lock = NSLock()
    private var running = false
    private var unavailable = false
    private var desiredRate: Double = 32728
    private var volume: Float = 1
    private var muted = false
    private var state = "idle"
    private var failureName: String?
    private var failureReason: String?
    private var failureFrames: String?
    private var startError: String?
    private var observers: [NSObjectProtocol] = []

    private init() {
        scratch = UnsafeMutablePointer<Int16>.allocate(capacity: scratchFrames * 2)
        scratch.initialize(repeating: 0, count: scratchFrames * 2)
        observe()
    }

    // MARK: - Lifecycle

    /// Starts (or restarts) playback at the core's rate. Safe to call twice, and
    /// safe to call after a failure: a refused graph leaves audio off, not the
    /// app down.
    func start(sampleRate: Double) {
        lock.lock()
        let rate = sampleRate.isFinite && sampleRate > 1000 ? sampleRate : 32728
        let changedRate = abs(rate - desiredRate) > 0.5
        desiredRate = rate
        let alreadyRunning = running && !unavailable && engine.isRunning && !changedRate
        let off = unavailable
        lock.unlock()

        guard !off else { return }

        activateSession()
        if isUnavailable { return }
        if alreadyRunning { return }

        if changedRate || sourceNode == nil {
            buildEngine()
        } else {
            startEngine()
        }
    }

    /// Configures the session ahead of the first game, so the first frames of
    /// audio are not spent waiting for activation.
    func prepare() {
        activateSession()
    }

    func stop() {
        _ = AZTryCatch { [self] in
            engine.stop()
            if let node = sourceNode {
                engine.detach(node)
            }
            sourceNode = nil
            engine = AVAudioEngine()
        }

        lock.lock()
        running = false
        unavailable = false
        failureName = nil
        failureReason = nil
        failureFrames = nil
        startError = nil
        state = "stopped"
        lock.unlock()

        // Silent on purpose: a stopped engine should not leave the app holding
        // the session, and a refusal here is not worth reporting.
        _ = AZTryCatch { [self] in
            do {
                try AVAudioSession.sharedInstance().setActive(false,
                                                              options: .notifyOthersOnDeactivation)
            } catch {
                self.lock.lock()
                self.state = "stopped · session still held"
                self.lock.unlock()
            }
        }
    }

    var isUnavailable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return unavailable
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
        guard !isUnavailable else { return }
        ring.write(frames, frameCount: frameCount)
    }

    func snapshot() -> Counters {
        let ringState = ring.snapshot()
        lock.lock()
        let rate = desiredRate
        let runningNow = running
        let note = state
        let off = unavailable
        let name = failureName
        let reason = failureReason
        let frames = failureFrames
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
        counters.available = !off
        counters.state = note
        counters.failureName = name
        counters.failureReason = reason
        counters.failureFrames = frames

        if runningNow && !engineAlive && !off {
            counters.state = "engine stopped"
        }
        return counters
    }

    // MARK: - Engine

    private func buildEngine() {
        lock.lock()
        let rate = desiredRate
        lock.unlock()

        // Deinterleaved float is the format AVAudioEngine's graph is built for.
        // An interleaved format raises "required condition is false" from inside
        // AVFAudio as soon as the node is connected, which is what aborted the
        // app at launch before this was spelled out.
        guard let audioFormat = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else {
            disable(["name": "AVAudioFormat",
                     "reason": "a \(Int(rate)) Hz stereo format could not be created"])
            return
        }

        let problem = AZTryCatch { [self] in
            engine.stop()
            if let node = sourceNode {
                engine.detach(node)
            }
            sourceNode = nil
            engine = AVAudioEngine()

            let node = AVAudioSourceNode(format: audioFormat) { [weak self] _, _, frameCount, bufferList -> OSStatus in
                guard let self = self else { return noErr }
                return self.render(frameCount: frameCount, into: bufferList)
            }
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: audioFormat)
            sourceNode = node
        }

        if let problem = problem {
            disable(problem)
            return
        }

        applyVolume()
        startEngine()
    }

    private func startEngine() {
        guard sourceNode != nil else {
            buildEngine()
            return
        }

        lock.lock()
        startError = nil
        lock.unlock()

        let problem = AZTryCatch { [self] in
            do {
                try engine.start()
            } catch {
                lock.lock()
                startError = error.localizedDescription
                lock.unlock()
            }
        }

        if let problem = problem {
            disable(problem)
            return
        }

        lock.lock()
        let thrown = startError
        startError = nil
        if let thrown = thrown {
            running = false
            state = "engine start failed · \(thrown)"
            lock.unlock()
            return
        }
        running = true
        state = describeSession(prefix: "playing")
        lock.unlock()
    }

    /// Switches audio off for the rest of this session and records why. Nothing
    /// here can propagate: this is the last stop before the app would die.
    private func disable(_ problem: [String: String]) {
        let name = problem["name"] ?? "NSException"
        let reason = problem["reason"] ?? "no reason given"
        let frames = problem["callStack"] ?? ""

        lock.lock()
        unavailable = true
        running = false
        failureName = name
        failureReason = reason
        failureFrames = frames
        state = "unavailable · \(name): \(reason)"
        lock.unlock()

        let line = "audio unavailable · \(name): \(reason) · \(frames)"
        NSLog("[Azahar] %@", line)
        AZAppendAudioFailure(line)

        _ = AZTryCatch { [self] in
            engine.stop()
            if let node = sourceNode {
                engine.detach(node)
            }
            sourceNode = nil
            engine = AVAudioEngine()
        }
    }

    private func applyVolume() {
        lock.lock()
        let level = muted ? 0 : volume
        let attached = sourceNode != nil
        lock.unlock()
        guard attached else { return }

        if let problem = AZTryCatch({ [self] in
            engine.mainMixerNode.outputVolume = level
        }) {
            disable(problem)
        }
    }

    private func render(frameCount: AVAudioFrameCount,
                        into bufferList: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let frames = Int(frameCount)
        let list = UnsafeMutableAudioBufferListPointer(bufferList)
        let wanted = min(frames, scratchFrames)
        let read = ring.read(into: scratch, frameCount: wanted)
        let available = max(0, min(read, wanted))
        let scale: Float = 1.0 / 32768.0

        if list.count >= 2 {
            // Deinterleaved: one buffer per channel, which is the format the
            // source node is built with.
            for channel in 0..<list.count {
                guard let raw = list[channel].mData else { continue }
                let out = raw.assumingMemoryBound(to: Float.self)
                if channel < 2 {
                    var index = 0
                    while index < frames {
                        out[index] = index < available
                            ? Float(scratch[index * 2 + channel]) * scale
                            : 0
                        index += 1
                    }
                } else {
                    memset(raw, 0, frames * MemoryLayout<Float>.size)
                }
            }
        } else if let first = list.first, let raw = first.mData {
            // Interleaved: one buffer holding both channels. Defensive only, but
            // writing the wrong shape here is an EXC_BAD_ACCESS rather than an
            // exception, so it is worth handling.
            let out = raw.assumingMemoryBound(to: Float.self)
            let needed = frames * 2
            var index = 0
            while index < needed {
                out[index] = index < available * 2 ? Float(scratch[index]) * scale : 0
                index += 1
            }
        }

        return noErr
    }

    // MARK: - Session

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        var thrown: String?

        let problem = AZTryCatch {
            do {
                try session.setCategory(.playback, mode: .default, options: [])
                try session.setActive(true)
            } catch {
                thrown = error.localizedDescription
            }
        }

        if let problem = problem {
            disable(problem)
            return
        }

        lock.lock()
        defer { lock.unlock() }
        if let thrown = thrown {
            // Not fatal: the graph may still run, and a call that is ending will
            // be followed by a resume.
            state = "session failed · \(thrown)"
        } else if !unavailable {
            state = describeSession(prefix: running ? "playing" : "ready")
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
            _ = AZTryCatch { [self] in
                engine.pause()
            }
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
        guard wantsEngine else { return }
        buildEngine()
    }

    private func handleMediaServicesReset() {
        guard wantsEngine else { return }
        activateSession()
        if isUnavailable { return }
        buildEngine()
    }

    private func resumeIfWanted(reason: String) {
        guard wantsEngine else { return }
        guard !isUnavailable else { return }

        activateSession()
        if isUnavailable { return }

        if engine.isRunning { return }
        if sourceNode == nil {
            buildEngine()
        } else {
            let problem = AZTryCatch { [self] in
                do {
                    try engine.start()
                } catch {
                    lock.lock()
                    startError = error.localizedDescription
                    lock.unlock()
                }
            }
            if let problem = problem {
                disable(problem)
                return
            }
            lock.lock()
            running = true
            state = describeSession(prefix: reason)
            lock.unlock()
        }
    }

    private var wantsEngine: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }
}

/// Writes the audio failure to the core's log directory, where the diagnostics
/// screen points and where a bug report can find it later.
private func AZAppendAudioFailure(_ line: String) {
    guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
    let directory = documents.appendingPathComponent("Azahar/log", isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("frontend-crash.log")
        let stamp = ISO8601DateFormatter().string(from: Date())
        let text = "\(stamp) \(line)\n"
        guard let data = text.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try data.write(to: url)
        }
    } catch {
        NSLog("[Azahar] audio failure could not be logged: %@", error.localizedDescription)
    }
}
