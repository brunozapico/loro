@preconcurrency import AVFoundation
import AudioEngineSafety
import Foundation
import LoroCore

/// Engine lifecycle stays on main; the real-time tap owns only its converter
/// and a bounded, synchronized buffer for this recording.
@MainActor
final class AudioCapture {
    enum CaptureError: Error {
        case microphonePermissionRequired
        case deviceUnavailable
        case converterCreationFailed
    }

    static let targetSampleRate: Double = 16_000
    static let maximumDuration: TimeInterval = 5 * 60
    private var generation = UUID()
    private var engine: AVAudioEngine?
    private var buffer: RecordingBuffer?
    private var configurationObserver: NSObjectProtocol?

    var onLevel: ((Float) -> Void)?
    var onInterruption: (() -> Void)?
    var onLimit: (() -> Void)?

    func start() throws {
        guard engine == nil else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw CaptureError.microphonePermissionRequired
        }
        let engine = AVAudioEngine()
        guard let inputFormat = LoroAudioInputFormat(engine),
              inputFormat.sampleRate.isFinite, inputFormat.sampleRate > 0,
              inputFormat.channelCount > 0 else { throw CaptureError.deviceUnavailable }
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: Self.targetSampleRate,
            channels: 1, interleaved: false
        ), let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw CaptureError.converterCreationFailed
        }
        let buffer = RecordingBuffer(limit: Int(Self.maximumDuration * Self.targetSampleRate))
        let generation = UUID()
        self.generation = generation
        self.engine = engine
        self.buffer = buffer
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.engine != nil, self.generation == generation else { return }
                // Starting the engine can itself produce a configuration
                // notification. Only interrupt when capture actually changed.
                if engine.isRunning,
                   let current = LoroAudioInputFormat(engine),
                   current.sampleRate == inputFormat.sampleRate,
                   current.channelCount == inputFormat.channelCount { return }
                self.onInterruption?()
            }
        }
        var startError: NSError?
        let started = LoroStartAudioEngine(engine, { @Sendable [weak self] input, _ in
            guard input.format.sampleRate == inputFormat.sampleRate,
                  input.format.channelCount == inputFormat.channelCount else {
                Task { @MainActor in
                    guard let self, self.engine != nil, self.generation == generation else { return }
                    self.onInterruption?()
                }
                return
            }
            let chunk = Self.convert(input, with: converter, to: targetFormat)
            let reachedLimit = buffer.append(chunk)
            let level = computeRMS(chunk)
            Task { @MainActor in
                guard let self, self.engine != nil, self.generation == generation else { return }
                self.onLevel?(level)
                if reachedLimit { self.onLimit?() }
            }
        }, &startError)
        if !started {
            stop()
            throw startError ?? NSError(domain: "com.brunozapico.loro.audio", code: 1)
        }
    }

    @discardableResult
    func stop() -> [Float] {
        if let observer = configurationObserver {
            NotificationCenter.default.removeObserver(observer)
            configurationObserver = nil
        }
        let captured = buffer?.finish() ?? []
        buffer = nil
        if let engine { LoroStopAudioEngine(engine) }
        engine = nil
        return captured
    }

    nonisolated private static func convert(
        _ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter, to format: AVAudioFormat
    ) -> [Float] {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return [] }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, status in
            guard !consumed else {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard status != .error, let data = output.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(output.frameLength)))
    }
}

func computeRMS(_ samples: [Float]) -> Float {
    guard !samples.isEmpty else { return 0 }
    let sum = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
    return Float((sum / Double(samples.count)).squareRoot())
}
