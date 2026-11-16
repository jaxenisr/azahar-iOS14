import Foundation

/// The audio path's short memory: one sample a second, the last sixty.
///
/// The counters the audio path keeps are cumulative, which answers "has this ever
/// gone wrong" but not "is it going wrong now". This keeps a minute of them, so a
/// burst of underruns on a loading screen stops colouring the current minute, and
/// it measures the size of a batch of audio the core actually hands over instead
/// of assuming one.
///
/// From those two comes the number the buffer comparison needs: how many frames
/// the buffer has to hold to stay ahead, derived from the measured rate and never
/// from the nominal sample rate.
final class AudioHealth {
    struct Feedback: Equatable {
        var underrunsLastMinute: UInt64 = 0
        var droppedLastMinute: UInt64 = 0
        var producedPerSecond: Double = 0
        var callbacksPerSecond: Double = 0
        /// Frames per `audio_sample_batch` call, measured.
        var batchFrames: Double = 0
        /// How much of the last minute the window actually covers.
        var windowSeconds: Double = 0
        var currentBufferMilliseconds: Double = 0
        var recommendedBufferMilliseconds: Double = 0
        var verdict = "waiting for a second of audio"
    }

    static let shared = AudioHealth()

    private struct Sample {
        var at: Date
        var underruns: UInt64
        var dropped: UInt64
        var produced: UInt64
        var callbacks: UInt64
        var coreRate: Double
    }

    private var samples: [Sample] = []
    private let window: TimeInterval = 60

    private init() {}

    /// Records one observation and answers what the last minute looks like.
    func record(counters: AudioOutput.Counters, callbacks: UInt64, now: Date) -> Feedback {
        samples.append(Sample(at: now,
                              underruns: counters.underruns,
                              dropped: counters.dropped,
                              produced: counters.produced,
                              callbacks: callbacks,
                              coreRate: counters.coreSampleRate))
        samples.removeAll { now.timeIntervalSince($0.at) > window }

        var feedback = Feedback()
        feedback.currentBufferMilliseconds = counters.latencyMilliseconds

        guard let first = samples.first, let last = samples.last, samples.count > 1 else {
            return feedback
        }

        let elapsed = max(last.at.timeIntervalSince(first.at), 0.001)
        feedback.windowSeconds = elapsed
        feedback.underrunsLastMinute = last.underruns &- first.underruns
        feedback.droppedLastMinute = last.dropped &- first.dropped
        feedback.producedPerSecond = Double(last.produced &- first.produced) / elapsed
        feedback.callbacksPerSecond = Double(last.callbacks &- first.callbacks) / elapsed

        if feedback.callbacksPerSecond > 0.1 {
            feedback.batchFrames = feedback.producedPerSecond / feedback.callbacksPerSecond
        }

        let rate = last.coreRate > 1000 ? last.coreRate : counters.coreSampleRate
        if rate > 1000, feedback.batchFrames > 0 {
            // Two batches of headroom: never so little that the render thread is
            // waiting on the emulation thread's next frame, and never so much that
            // the extra is heard as lag rather than as safety.
            feedback.recommendedBufferMilliseconds = feedback.batchFrames * 2 / rate * 1000
        }

        if feedback.producedPerSecond < 1 {
            feedback.verdict = "The core is producing nothing, so a buffer target would be meaningless. Start a title and come back."
        } else if feedback.underrunsLastMinute == 0 {
            feedback.verdict = "No underruns in the last minute."
        } else if feedback.recommendedBufferMilliseconds > 0,
                  feedback.currentBufferMilliseconds < feedback.recommendedBufferMilliseconds {
            feedback.verdict = "Underruns with less buffer than the two-batch target: the render thread is arriving before the emulation thread has produced the next batch."
        } else {
            feedback.verdict = "Underruns with enough buffer: the emulation thread is pausing, not the buffer being too small."
        }
        return feedback
    }

    /// Zeroes the window, so a measurement can start from the current moment
    /// instead of from whatever happened before the screen was opened.
    func reset() {
        samples.removeAll()
    }
}
