import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let shortcutRecorder: ShortcutRecorderModel

    init(
        store: SettingsStore,
        model: TranscriptionModel,
        overlayAllowed: Bool,
        onShortcutRecordingChanged: @escaping (Bool) -> Void
    ) {
        let shortcutRecorder = ShortcutRecorderModel()
        self.shortcutRecorder = shortcutRecorder

        let rootView = SettingsView(
            store: store,
            model: model,
            overlayAllowed: overlayAllowed,
            shortcutRecorder: shortcutRecorder,
            onShortcutRecordingChanged: onShortcutRecordingChanged
        )
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Parrot Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 480, height: 430))
        window.center()

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        shortcutRecorder.cancel()
        window?.resignKey()
    }
}

private struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    let model: TranscriptionModel
    let overlayAllowed: Bool
    @ObservedObject var shortcutRecorder: ShortcutRecorderModel
    let onShortcutRecordingChanged: (Bool) -> Void

    var body: some View {
        Form {
            Section("Shortcut") {
                LabeledContent("Global shortcut") {
                    ShortcutRecorderControl(
                        shortcut: $store.shortcut,
                        recorder: shortcutRecorder,
                        onRecordingChanged: onShortcutRecordingChanged
                    )
                }
                Text("Click the shortcut, then press any key combination. Press Escape to cancel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Dictation") {
                Picker("Activation", selection: $store.dictationMode) {
                    ForEach(DictationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(store.dictationMode.helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Show recording overlay", isOn: $store.showOverlay)
                    .disabled(!overlayAllowed)

                if !overlayAllowed {
                    Text("The overlay is disabled for this session by the --no-overlay command-line option.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Model") {
                LabeledContent("Selected model", value: model.displayName)
                LabeledContent("Identifier", value: model.id)
                LabeledContent("Languages", value: languageDescription)
                LabeledContent("Download size", value: "\(model.sizeMB) MB")
            }

            Section {
                HStack {
                    Spacer()
                    Button("Restore Defaults") {
                        store.resetToDefaults()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 430)
    }

    private var languageDescription: String {
        model.languages == ["multi"] ? "Multilingual" : model.languages.joined(separator: ", ")
    }
}

private struct ShortcutRecorderControl: View {
    @Binding var shortcut: HotkeyShortcut
    @ObservedObject var recorder: ShortcutRecorderModel
    let onRecordingChanged: (Bool) -> Void

    var body: some View {
        Button {
            if recorder.isRecording {
                recorder.cancel()
            } else {
                recorder.start(
                    onRecordingChanged: onRecordingChanged,
                    onCapture: { shortcut = $0 }
                )
            }
        } label: {
            Text(recorder.isRecording ? "Press shortcut…" : shortcut.displayName)
                .fontDesign(.monospaced)
                .frame(minWidth: 120)
        }
        .onDisappear {
            recorder.cancel()
        }
    }
}

@MainActor
private final class ShortcutRecorderModel: ObservableObject {
    @Published private(set) var isRecording = false

    private var eventMonitor: Any?
    private var pendingModifiers: UInt64 = 0
    private var onCapture: ((HotkeyShortcut) -> Void)?
    private var onRecordingChanged: ((Bool) -> Void)?

    func start(
        onRecordingChanged: @escaping (Bool) -> Void,
        onCapture: @escaping (HotkeyShortcut) -> Void
    ) {
        cancel()
        self.onRecordingChanged = onRecordingChanged
        self.onCapture = onCapture
        isRecording = true
        pendingModifiers = 0
        onRecordingChanged(true)

        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .flagsChanged]
        ) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    func cancel() {
        let recordingChanged = onRecordingChanged
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
        pendingModifiers = 0
        onCapture = nil
        onRecordingChanged = nil
        isRecording = false
        recordingChanged?(false)
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .keyDown:
            if event.keyCode == 53 {
                cancel()
                return nil
            }

            let shortcut = HotkeyShortcut(
                keyCode: event.keyCode,
                modifiers: HotkeyShortcut.normalized(event.modifierFlags),
                keyLabel: Self.keyLabel(for: event)
            )
            finish(with: shortcut)
            return nil

        case .flagsChanged:
            let currentModifiers = HotkeyShortcut.normalized(event.modifierFlags)
            if currentModifiers != 0 {
                pendingModifiers |= currentModifiers
                return nil
            }

            if pendingModifiers != 0 {
                let shortcut = HotkeyShortcut(
                    keyCode: nil,
                    modifiers: pendingModifiers,
                    keyLabel: ""
                )
                finish(with: shortcut)
            }
            return nil

        default:
            return event
        }
    }

    private func finish(with shortcut: HotkeyShortcut) {
        let callback = onCapture
        cancel()
        callback?(shortcut)
    }

    private static func keyLabel(for event: NSEvent) -> String {
        let specialKeys: [UInt16: String] = [
            36: "↩",
            48: "⇥",
            49: "Space",
            51: "⌫",
            53: "Esc",
            71: "Clear",
            76: "⌅",
            117: "⌦",
            115: "Home",
            116: "Page Up",
            119: "End",
            121: "Page Down",
            123: "←",
            124: "→",
            125: "↓",
            126: "↑",
            122: "F1",
            120: "F2",
            99: "F3",
            118: "F4",
            96: "F5",
            97: "F6",
            98: "F7",
            100: "F8",
            101: "F9",
            109: "F10",
            103: "F11",
            111: "F12",
        ]
        if let special = specialKeys[event.keyCode] {
            return special
        }
        return event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
    }
}
