import Foundation
import Testing
@testable import LoroCore

struct StabilityTests {
    @Test func recordingIsBoundedAndReportsLimitOnce() {
        let buffer = RecordingBuffer(limit: 4)
        #expect(!buffer.append([1, 2]))
        #expect(buffer.append([3, 4, 5, 6]))
        #expect(!buffer.append([7]))
        #expect(buffer.finish() == [1, 2, 3, 4])
    }

    @Test func lateAudioCannotContaminateTheNextRecording() {
        let first = RecordingBuffer(limit: 10)
        _ = first.append([1])
        #expect(first.finish() == [1])
        let second = RecordingBuffer(limit: 10)
        _ = first.append([99])
        _ = second.append([2])
        #expect(first.finish().isEmpty)
        #expect(second.finish() == [2])
    }

    @Test func concurrentAudioAndStopRemainSafe() {
        let buffer = RecordingBuffer(limit: 1000)
        DispatchQueue.concurrentPerform(iterations: 200) { i in
            if i == 100 { _ = buffer.finish() }
            else { _ = buffer.append([Float(i)]) }
        }
        #expect(buffer.finish().isEmpty)
    }

    @Test func completedOperationReturnsItsValue() async throws {
        let runner = TimedOperation<String>()
        let result = try await runner.run(timeoutNanoseconds: 1_000_000_000) { "ready" }
        #expect(result == "ready")
        let next = try await runner.run(timeoutNanoseconds: 1_000_000_000) { "again" }
        #expect(next == "again")
    }

    @Test func deadlineDoesNotWaitForUncooperativeWorkerOrStartAnother() async throws {
        let gate = WorkerGate()
        let runner = TimedOperation<String>()
        let start = ContinuousClock.now
        await #expect(throws: TimedOperationError.timedOut) {
            try await runner.run(timeoutNanoseconds: 30_000_000) {
                await gate.wait()
                return "late"
            }
        }
        #expect(start.duration(to: .now) < .seconds(1))
        await #expect(throws: TimedOperationError.busy) {
            try await runner.run(timeoutNanoseconds: 1_000_000_000) { "must not run" }
        }
        await gate.release()
    }

    @Test func cancellationReturnsWithoutWaitingForFramework() async throws {
        let gate = WorkerGate()
        let runner = TimedOperation<String>()
        let task = Task {
            try await runner.run(timeoutNanoseconds: 10_000_000_000) {
                await gate.wait()
                return "late"
            }
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        task.cancel()
        let start = ContinuousClock.now
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(start.duration(to: .now) < .seconds(1))
        await gate.release()
    }
}

private actor WorkerGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
