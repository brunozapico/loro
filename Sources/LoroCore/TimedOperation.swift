import Foundation

public enum TimedOperationError: Error, Equatable {
    case busy
    case timedOut
}

/// A deadline that returns even when a framework ignores cancellation. Only
/// one worker is allowed: timed-out inference cannot accumulate in memory.
public actor TimedOperation<Value: Sendable> {
    private var running = false

    public init() {}

    public func run(
        timeoutNanoseconds: UInt64,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try Task.checkCancellation()
        guard !running else { throw TimedOperationError.busy }
        running = true
        let (stream, continuation) = AsyncStream<Result<Value, Error>>.makeStream(
            bufferingPolicy: .bufferingOldest(1)
        )
        let worker = Task.detached {
            let result: Result<Value, Error>
            do { result = .success(try await operation()) }
            catch { result = .failure(error) }
            await self.finished()
            continuation.yield(result)
            continuation.finish()
        }
        let timer = Task.detached {
            do { try await Task.sleep(nanoseconds: timeoutNanoseconds) }
            catch { return }
            continuation.yield(.failure(TimedOperationError.timedOut))
            continuation.finish()
        }
        defer {
            worker.cancel()
            timer.cancel()
        }
        var iterator = stream.makeAsyncIterator()
        guard let result = await iterator.next() else { throw CancellationError() }
        try Task.checkCancellation()
        return try result.get()
    }

    private func finished() { running = false }
}
