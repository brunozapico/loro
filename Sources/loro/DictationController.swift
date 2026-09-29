import AppKit
import Foundation
import LoroCore
import OSLog

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
    private var copyToClipboard: Bool
    private var stopOnSilence: Bool
    private var silenceTimeoutSeconds: Int
    private var correctionMode: CorrectionMode
    private var enableLocalCorrection: Bool
    private var replacementRules: [ReplacementRule]
    private var silenceDetector: SilenceDetector
    private var silenceTimer: Timer?
    private var recordingDeadlineTimer: Timer?
    private var recordingApplicationIdentifier = "unknown-application"
    private let inference = TimedOperation<String>()
    private var transcriptionTask: Task<Void, Never>?
    private var modelReady = false
    private var shuttingDown = false
    private static let logger = Logger(subsystem: "com.brunozapico.loro", category: "dictation")
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
        self.copyToClipboard = settings.copyToClipboard
        self.stopOnSilence = settings.stopOnSilence
        self.silenceTimeoutSeconds = settings.silenceTimeoutSeconds
        self.correctionMode = settings.correctionMode
        self.enableLocalCorrection = settings.enableLocalCorrection
        self.replacementRules = settings.replacementRules
        self.silenceDetector = SilenceDetector(
            timeout: TimeInterval(settings.silenceTimeoutSeconds)
        )
        self.overlayAllowed = overlayAllowed
    }

    func setModelReady() { modelReady = true }

    func shutdown() {
        shuttingDown = true
        transcriptionTask?.cancel()
        transcriptionTask = nil
        stopSilenceMonitoring()
        recordingDeadlineTimer?.invalidate()
        recordingDeadlineTimer = nil
        capture.stop()
        isRecording = false
        overlay.hide()
        correctionManager.clearContext()
    }

    func handle(_ event: HotkeyMonitor.Event) {
        guard modelReady, !shuttingDown else { return }
        switch mode {
        case .pushToTalk:
            switch event {
            case .pressed: startRecording()
            case .released: stopAndTranscribe(reason: "shortcut released")
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
        let silenceSettingsChanged =
            stopOnSilence != settings.stopOnSilence
            || silenceTimeoutSeconds != settings.silenceTimeoutSeconds

        if mode != settings.dictationMode, isRecording {
            stopAndTranscribe()
        }
        mode = settings.dictationMode
        showOverlay = settings.showOverlay
        copyToClipboard = settings.copyToClipboard
        stopOnSilence = settings.stopOnSilence
        silenceTimeoutSeconds = settings.silenceTimeoutSeconds
        correctionMode = settings.correctionMode
        enableLocalCorrection = settings.enableLocalCorrection
        replacementRules = settings.replacementRules

        if silenceSettingsChanged, isRecording {
            startSilenceMonitoringIfNeeded()
        }

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
    func finishActiveRecording(reason: String = "settings or permissions changed") {
        if isRecording {
            stopAndTranscribe(reason: reason)
        }
    }

    /// AudioCapture calls this for every converted buffer. It is intentionally
    /// lightweight: only voice activity in Toggle mode resets the silence
    /// countdown.
    func handleAudioLevel(_ level: Float) {
        guard isRecording, mode == .toggle, stopOnSilence else { return }
        silenceDetector.observe(
            level: level,
            at: ProcessInfo.processInfo.systemUptime
        )
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
            Self.logger.notice("Recording started")
            let deadline = Timer(timeInterval: AudioCapture.maximumDuration, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.finishActiveRecording(reason: "recording duration limit") }
            }
            recordingDeadlineTimer = deadline
            RunLoop.main.add(deadline, forMode: .common)
            startSilenceMonitoringIfNeeded()
            if overlayIsEnabled {
                overlay.show(.recording)
            }
            menuBar.setRecording(true)
        } catch {
            overlay.hide()
            Self.logger.error("Microphone capture failed")
            menuBar.setError("Microphone unavailable — check Permissions and input device")
        }
    }

    private func stopAndTranscribe(reason: String = "toggle or mode changed") {
        guard isRecording else { return }
        isRecording = false
        recordingDeadlineTimer?.invalidate()
        recordingDeadlineTimer = nil
        stopSilenceMonitoring()

        let samples = capture.stop()
        Self.logger.notice("Recording stopped: \(reason, privacy: .public); samples: \(samples.count)")
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
        let correctionMode = correctionMode
        let enableLocalCorrection = enableLocalCorrection
        let applicationIdentifier = recordingApplicationIdentifier
        let protectedPhrases = replacementRules.map(\.spokenPhrase)

        transcriptionTask = Task { [weak self, transcriber, correctionManager, inference] in
            do {
                let text = try await inference.run(timeoutNanoseconds: 120_000_000_000) {
                    try await transcriber.transcribe(samples)
                }
                try Task.checkCancellation()
                let correctedText = await correctionManager.correct(
                    text,
                    protectedPhrases: protectedPhrases,
                    applicationIdentifier: applicationIdentifier,
                    enabled: enableLocalCorrection,
                    mode: correctionMode
                )
                try Task.checkCancellation()
                guard let self, !self.shuttingDown else { return }
                let processedText = TextReplacementEngine.apply(
                    replacementRules,
                    to: correctedText
                )
                let injectionSucceeded = TextInjector.inject(processedText)
                if TranscriptionDeliveryPolicy.shouldCopy(
                    automaticCopyEnabled: self.copyToClipboard,
                    injectionSucceeded: injectionSucceeded
                ) {
                    ClipboardWriter.copy(processedText)
                }
                await correctionManager.remember(
                    processedText,
                    applicationIdentifier: applicationIdentifier,
                    enabled: enableLocalCorrection,
                    mode: correctionMode
                )
                self.isTranscribing = false
                self.overlay.hide()
                self.menuBar.setRecording(false)
            } catch {
                guard let self, !self.shuttingDown else { return }
                self.isTranscribing = false
                self.overlay.hide()
                Self.logger.error("Transcription failed or exceeded deadline")
                self.menuBar.setError("Transcription unavailable — retry or restart Loro")
            }
        }
    }

    private func startSilenceMonitoringIfNeeded() {
        stopSilenceMonitoring()
        guard isRecording, mode == .toggle, stopOnSilence else { return }

        let now = ProcessInfo.processInfo.systemUptime
        silenceDetector = SilenceDetector(
            timeout: TimeInterval(silenceTimeoutSeconds)
        )
        silenceDetector.start(at: now)

        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkSilenceTimeout()
            }
        }
        silenceTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func checkSilenceTimeout() {
        guard isRecording, mode == .toggle, stopOnSilence else {
            stopSilenceMonitoring()
            return
        }

        if silenceDetector.shouldStop(at: ProcessInfo.processInfo.systemUptime) {
            stopAndTranscribe(reason: "silence timeout")
        }
    }

    private func stopSilenceMonitoring() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        silenceDetector.reset()
    }

    private static func frontmostApplicationIdentifier() -> String {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return "unknown-application"
        }
        return application.bundleIdentifier ?? "pid:\(application.processIdentifier)"
    }
}
