import AVFoundation
import Foundation
import Testing
import WhisperKit
@testable import loro

/// Opt in locally: uses a synthetic voice fixture, never the user's microphone.
struct TranscriptionIntegrationTests {
    @Test @MainActor func nativeAppUsesItsStandardPreferencesDomain() {
        #expect(SettingsStore.makeDefaults(bundleIdentifier: "com.brunozapico.loro") === UserDefaults.standard)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LORO_RUN_MODEL_TESTS"] == "1"))
    func transcribesSyntheticSpeechWithTheRealModel() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let audioURL = directory.appendingPathComponent("fixture.aiff")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", "Samantha", "-o", audioURL.path, "Hello world. This is a test of local dictation."]
        try say.run()
        say.waitUntilExit()
        #expect(say.terminationStatus == 0)
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioURL.path)
        let transcriber = WhisperKitTranscriber(model: ModelRegistry.recommended()!)
        try await transcriber.warmUp()
        let transcript = try await transcriber.transcribe(samples)
        #expect(transcript.lowercased().contains("hello world"))
        #expect(transcript.lowercased().contains("dictation"))
    }

    @Test @MainActor func deniedMicrophoneFailsWithoutStartingAnEngine() throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) != .authorized else { return }
        let capture = AudioCapture()
        #expect(throws: AudioCapture.CaptureError.self) { try capture.start() }
        #expect(capture.stop().isEmpty)
        #expect(capture.stop().isEmpty)
    }
}
