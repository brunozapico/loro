import Foundation

/// Each tap owns a separate buffer. Late callbacks from a stopped engine can
/// never append to a subsequent recording. The limit also bounds retained RAM.
public final class RecordingBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var samples: [Float] = []
    private var accepting = true
    private var reportedLimit = false

    public init(limit: Int) { self.limit = max(0, limit) }

    /// Returns true only once, when the duration limit is reached.
    public func append(_ chunk: [Float]) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard accepting else { return false }
        samples.append(contentsOf: chunk.prefix(max(0, limit - samples.count)))
        guard samples.count == limit, !reportedLimit else { return false }
        reportedLimit = true
        return true
    }

    public func finish() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        accepting = false
        let result = samples
        samples = []
        return result
    }
}
