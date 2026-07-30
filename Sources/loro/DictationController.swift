import AppKit
import Foundation

/// Owns the recording lifecycle so shortcut behavior can change at runtime
/// without duplicating audio or transcription state in the CLI entry point.
@MainActor
final class DictationController {
    private let capture: AudioCapture
    private let transcriber: WhisperKitTranscriber
    private let overlay: RecordingOverlay
    private let menuBar: MenuBarController
    private let correctionManager: LocalCorrectionManager
    private let overlayAllowed: Bool

    private var mode: DictationMode
    private var showOverlay: Bool
    private var enableLocalCorrection: Bool
    private var replacementRules: [ReplacementRule]
    private var recordingApplicationIdentifier = "unknown-application"
    private var isRecording = false
    private var isTranscribing = false

    init(
        capture: AudioCapture,
        transcriber: WhisperKitTranscriber,
        overlay: RecordingOverlay,
        menuBar: MenuBarController,
        correctionManager: LocalCorrectionManager,
        settings: AppSettings,
        overlayAllowed: Bool
    ) {
        self.capture = capture
        self.transcriber = transcriber
        self.overlay = overlay
        self.menuBar = menuBar
        self.correctionManager = correctionManager
        self.mode = settings.dictationMode
        self.showOverlay = settings.showOverlay
        self.enableLocalCorrection = settings.enableLocalCorrection
        self.replacementRules = settings.replacementRules
        self.overlayAllowed = overlayAllowed
    }

    func handle(_ event: HotkeyMonitor.Event) {
        switch mode {
        case .pushToTalk:
            switch event {
            case .pressed: startRecording()
            case .released: stopAndTranscribe()
            }
        case .toggle:
            guard event == .pressed else { return }
            if isRecording {
                stopAndTranscribe()
            } else {
                startRecording()
            }
        }
    }

    func apply(_ settings: AppSettings) {
        if mode != settings.dictationMode, isRecording {
            stopAndTranscribe()
        }
        mode = settings.dictationMode
        showOverlay = settings.showOverlay
        enableLocalCorrection = settings.enableLocalCorrection
        replacementRules = settings.replacementRules
        if isRecording, overlayIsEnabled {
            overlay.show(.recording)
        } else if isTranscribing, overlayIsEnabled {
            overlay.show(.transcribing)
        } else if !overlayIsEnabled {
            overlay.hide()
        }
    }

    /// Finish a capture before replacing its shortcut so releasing the old
    /// shortcut cannot leave the microphone active.
    func finishActiveRecording() {
        if isRecording {
            stopAndTranscribe()
        }
    }

    private var overlayIsEnabled: Bool {
        overlayAllowed && showOverlay
    }

    private func startRecording() {
        guard !isRecording, !isTranscribing else { return }
        do {
            recordingApplicationIdentifier = Self.frontmostApplicationIdentifier()
            try capture.start()
            isRecording = true
            if overlayIsEnabled {
                overlay.show(.recording)
            }
            menuBar.setRecording(true)
        } catch {
            overlay.hide()
            menuBar.setError("microphone capture failed")
        }
    }

    private func stopAndTranscribe() {
        guard isRecording else { return }
        isRecording = false

        let samples = capture.stop()
        guard !samples.isEmpty else {
            overlay.hide()
            menuBar.setRecording(false)
            return
        }

        isTranscribing = true
        if overlayIsEnabled {
            overlay.show(.transcribing)
        } else {
            overlay.hide()
        }
        menuBar.setTranscribing()
        let replacementRules = replacementRules
        let enableLocalCorrection = enableLocalCorrection
        let applicationIdentifier = recordingApplicationIdentifier
        let protectedPhrases = replacementRules.map(\.spokenPhrase)

        Task { [weak self, transcriber, correctionManager] in
            do {
                let text = try await transcriber.transcribe(samples)
                let correctedText = await correctionManager.correct(
                    text,
                    protectedPhrases: protectedPhrases,
                    applicationIdentifier: applicationIdentifier,
                    enabled: enableLocalCorrection
                )
                guard let self else { return }
                self.isTranscribing = false
                let processedText = TextReplacementEngine.apply(
                    replacementRules,
                    to: correctedText
                )
                TextInjector.inject(processedText)
                await correctionManager.remember(
                    processedText,
                    applicationIdentifier: applicationIdentifier,
                    enabled: enableLocalCorrection
                )
                self.overlay.hide()
                self.menuBar.setRecording(false)
            } catch {
                guard let self else { return }
                self.isTranscribing = false
                self.overlay.hide()
                self.menuBar.setError("transcription failed")
            }
        }
    }

    private static func frontmostApplicationIdentifier() -> String {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return "unknown-application"
        }
        return application.bundleIdentifier ?? "pid:\(application.processIdentifier)"
    }
}
