import Foundation

/// Tracks voice activity using a monotonic clock supplied by the caller.
/// Keeping the timing logic independent from AVAudioEngine makes it
/// deterministic and straightforward to test.
public struct SilenceDetector {
    public static let defaultSpeechThreshold: Float = 0.012

    public var timeout: TimeInterval
    public var speechThreshold: Float

    private var lastVoiceActivity: TimeInterval?

    public init(
        timeout: TimeInterval,
        speechThreshold: Float = Self.defaultSpeechThreshold
    ) {
        self.timeout = max(0, timeout)
        self.speechThreshold = max(0, speechThreshold)
    }

    public mutating func start(at time: TimeInterval) {
        lastVoiceActivity = time
    }

    public mutating func observe(level: Float, at time: TimeInterval) {
        guard level.isFinite, level >= speechThreshold else { return }
        lastVoiceActivity = time
    }

    public func shouldStop(at time: TimeInterval) -> Bool {
        guard let lastVoiceActivity else { return false }
        return time - lastVoiceActivity >= timeout
    }

    public mutating func reset() {
        lastVoiceActivity = nil
    }
}
