import AppKit
import ArgumentParser
import Foundation
import LoroCore
import WhisperKit

@main
struct Loro: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "loro",
        abstract: "Spanish-first macOS dictation with a configurable global shortcut.",
        subcommands: [Run.self, Setup.self, Doctor.self, Models.self, Install.self],
        defaultSubcommand: Run.self
    )
}

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run the application (default)."
    )

    @Flag(name: .long, help: "Start without opening Settings.")
    var skipDoctor: Bool = false

    @Flag(name: .long, help: "Disable the on-screen recording overlay.")
    var noOverlay: Bool = false

    @Option(name: .long, help: "Model id for this run. Overrides the saved selection.")
    var model: String?

    func run() throws {
        let settingsStore = MainActor.assumeIsolated { SettingsStore() }
        let initialSettings = MainActor.assumeIsolated { settingsStore.current }

        let chosenModel: TranscriptionModel
        let modelIsOverridden = model != nil
        if let id = model {
            guard let m = ModelRegistry.find(id) else {
                throw ValidationError("Unknown model: \(id). Run `loro models list` to see options.")
            }
            chosenModel = m
        } else if let savedModel = ModelRegistry.find(initialSettings.selectedModelID) {
            chosenModel = savedModel
        } else {
            guard let m = ModelRegistry.recommended() else {
                throw ValidationError("No models registered.")
            }
            chosenModel = m
        }

        let transcriber = WhisperKitTranscriber(model: chosenModel)
        let app = NSApplication.shared
        if let existing = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.brunozapico.loro"
        ).first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate(options: [.activateAllWindows])
            return
        }
        let instance = try SingleInstanceLock()
        guard instance.acquired else {
            print("Loro is already running.")
            return
        }
        app.setActivationPolicy(.regular)

        let monitor = HotkeyMonitor(shortcut: initialSettings.shortcut)
        let capture = MainActor.assumeIsolated { AudioCapture() }
        let overlay = MainActor.assumeIsolated { RecordingOverlay() }
        let permissionManager = MainActor.assumeIsolated { PermissionManager() }
        let correctionManager = MainActor.assumeIsolated { LocalCorrectionManager() }

        let settingsWindow = MainActor.assumeIsolated {
            SettingsWindowController(
                store: settingsStore,
                activeModel: chosenModel,
                modelIsOverridden: modelIsOverridden,
                permissionManager: permissionManager,
                correctionManager: correctionManager,
                overlayAllowed: !noOverlay,
                onShortcutRecordingChanged: { isRecording in
                    monitor.setEnabled(!isRecording)
                }
            )
        }
        let menuBar = MainActor.assumeIsolated {
            MenuBarController(
                modelID: chosenModel.id,
                settings: initialSettings,
                onOpenSettings: { settingsWindow.show() },
                onClearContext: { correctionManager.clearContext() }
            )
        }
        let dictation = MainActor.assumeIsolated {
            DictationController(
                capture: capture,
                transcriber: transcriber,
                overlay: overlay,
                menuBar: menuBar,
                correctionManager: correctionManager,
                settings: initialSettings,
                overlayAllowed: !noOverlay
            )
        }
        MainActor.assumeIsolated {
            capture.onLevel = { level in
                overlay.pushLevel(level)
                dictation.handleAudioLevel(level)
                menuBar.updateAudioLevel(level)
            }
            capture.onInterruption = { dictation.finishActiveRecording(reason: "audio device interrupted") }
            capture.onLimit = { dictation.finishActiveRecording(reason: "audio buffer limit") }
        }

        MainActor.assumeIsolated {
            var appliedSettings = initialSettings
            settingsStore.onChange = { settings in
                if settings.shortcut != appliedSettings.shortcut {
                    dictation.finishActiveRecording()
                    monitor.updateShortcut(settings.shortcut)
                }
                if (appliedSettings.enableLocalCorrection && !settings.enableLocalCorrection)
                    || appliedSettings.correctionMode != settings.correctionMode {
                    correctionManager.clearContext()
                }
                dictation.apply(settings)
                menuBar.apply(settings)
                appliedSettings = settings
            }
        }

        let startHotkeyMonitoring = {
            guard !monitor.isRunning else { return }
            do {
                try monitor.start { event in
                    MainActor.assumeIsolated {
                        dictation.handle(event)
                    }
                }
            } catch {
                MainActor.assumeIsolated {
                    settingsWindow.show(tab: .permissions)
                }
            }
        }

        MainActor.assumeIsolated {
            permissionManager.onStatusChange = {
                if !permissionManager.microphoneGranted { dictation.finishActiveRecording() }
                if permissionManager.accessibilityGranted {
                    startHotkeyMonitoring()
                } else {
                    dictation.finishActiveRecording()
                    monitor.stop()
                }
            }
        }

        let delegate = MainActor.assumeIsolated {
            ApplicationDelegate(
                onOpen: {
                    settingsWindow.show(tab: permissionManager.allRequiredPermissionsGranted ? .general : .permissions)
                },
                onQuit: {
                    monitor.stop()
                    dictation.shutdown()
                }
            )
        }
        app.delegate = delegate
        MainActor.assumeIsolated { delegate.installMenu() }
        let warmupTask = Task { @MainActor in
            Install.migrateInstalledAgent()
            menuBar.setError("Loading transcription model…")
            // Show the app immediately, including permissions, while loading.
            if !skipDoctor { delegate.openSettings() }
            do {
                let loader = TimedOperation<Void>()
                try await loader.run(timeoutNanoseconds: 300_000_000_000) {
                    try await transcriber.warmUp()
                }
                try Task.checkCancellation()
                dictation.setModelReady()
                menuBar.setRecording(false)
                startHotkeyMonitoring()
            } catch is CancellationError {
                return
            } catch {
                menuBar.setError("Model could not load — check connection and restart Loro")
                let alert = NSAlert()
                alert.messageText = "Loro could not load its transcription model"
                alert.informativeText = "Check your connection and available disk space, then reopen Loro. You can also select a smaller model in Settings."
                alert.runModal()
            }
        }

        var signals: [DispatchSourceSignal] = []
        for number in [SIGINT, SIGTERM] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signals.append(source)
        }

        withExtendedLifetime((delegate, instance, signals, settingsStore, permissionManager)) {
            app.run()
        }
        warmupTask.cancel()
    }
}

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check microphone, accessibility, and shortcut configuration."
    )

    func run() throws {
        let shortcut = MainActor.assumeIsolated { SettingsStore().current.shortcut }
        let checks = DoctorReport.run(shortcut: shortcut)
        DoctorReport.print(checks)
        if !DoctorReport.allOK(checks) {
            throw ExitCode(1)
        }
    }
}

struct Models: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage transcription models.",
        subcommands: [List.self, Download.self]
    )

    struct List: ParsableCommand {
        func run() throws {
            for m in ModelRegistry.shared {
                let star = m.recommended ? "★" : " "
                let id = m.id.padding(toLength: 26, withPad: " ", startingAt: 0)
                let langs = "[\(m.languages.joined(separator: ","))]"
                    .padding(toLength: 9, withPad: " ", startingAt: 0)
                let size = String(format: "%5d MB", m.sizeMB)
                print("\(star) \(id) \(size)  \(langs)  \(m.displayName)")
            }
        }
    }

    struct Download: ParsableCommand {
        @Argument(help: "Model id to download.") var id: String

        func run() throws {
            guard let m = ModelRegistry.find(id) else {
                print("unknown model: \(id)")
                throw ExitCode(1)
            }
            let t = WhisperKitTranscriber(model: m)

            let sem = DispatchSemaphore(value: 0)
            var capturedError: Error?
            Task.detached {
                do { try await t.warmUp() } catch { capturedError = error }
                sem.signal()
            }
            sem.wait()
            if let e = capturedError { throw e }
        }
    }
}
