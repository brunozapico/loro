import AppKit
import SwiftUI

enum SettingsTab: Hashable {
    case general
    case dictionary
    case correction
    case permissions
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let shortcutRecorder: ShortcutRecorderModel
    private let navigation: SettingsNavigationModel
    private let permissionManager: PermissionManager
    private let correctionManager: LocalCorrectionManager

    init(
        store: SettingsStore,
        activeModel: TranscriptionModel,
        modelIsOverridden: Bool,
        permissionManager: PermissionManager,
        correctionManager: LocalCorrectionManager,
        overlayAllowed: Bool,
        onShortcutRecordingChanged: @escaping (Bool) -> Void
    ) {
        let shortcutRecorder = ShortcutRecorderModel()
        let navigation = SettingsNavigationModel()
        self.shortcutRecorder = shortcutRecorder
        self.navigation = navigation
        self.permissionManager = permissionManager
        self.correctionManager = correctionManager

        let rootView = SettingsView(
            store: store,
            activeModel: activeModel,
            modelIsOverridden: modelIsOverridden,
            permissionManager: permissionManager,
            correctionManager: correctionManager,
            overlayAllowed: overlayAllowed,
            shortcutRecorder: shortcutRecorder,
            navigation: navigation,
            onShortcutRecordingChanged: onShortcutRecordingChanged
        )
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Parrot Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 560, height: 500))
        window.center()

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(tab: SettingsTab? = nil) {
        guard let window else { return }
        if let tab {
            navigation.selectedTab = tab
        }
        permissionManager.refresh()
        correctionManager.refreshAvailability()
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        shortcutRecorder.cancel()
        window?.resignKey()
    }
}

@MainActor
private final class SettingsNavigationModel: ObservableObject {
    @Published var selectedTab: SettingsTab = .general
}

private struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    let activeModel: TranscriptionModel
    let modelIsOverridden: Bool
    @ObservedObject var permissionManager: PermissionManager
    @ObservedObject var correctionManager: LocalCorrectionManager
    let overlayAllowed: Bool
    @ObservedObject var shortcutRecorder: ShortcutRecorderModel
    @ObservedObject var navigation: SettingsNavigationModel
    let onShortcutRecordingChanged: (Bool) -> Void

    var body: some View {
        TabView(selection: $navigation.selectedTab) {
            GeneralSettingsView(
                store: store,
                activeModel: activeModel,
                modelIsOverridden: modelIsOverridden,
                overlayAllowed: overlayAllowed,
                shortcutRecorder: shortcutRecorder,
                onShortcutRecordingChanged: onShortcutRecordingChanged
            )
            .tabItem {
                Label("General", systemImage: "gearshape")
            }
            .tag(SettingsTab.general)

            DictionarySettingsView(store: store)
                .tabItem {
                    Label("Dictionary", systemImage: "character.book.closed")
                }
                .tag(SettingsTab.dictionary)

            CorrectionSettingsView(
                store: store,
                correctionManager: correctionManager
            )
            .tabItem {
                Label("Correction", systemImage: "wand.and.stars")
            }
            .tag(SettingsTab.correction)

            PermissionsSettingsView(permissionManager: permissionManager)
                .tabItem {
                    Label("Permissions", systemImage: "lock.shield")
                }
                .tag(SettingsTab.permissions)
        }
        .frame(width: 560, height: 500)
    }
}

private struct CorrectionSettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var correctionManager: LocalCorrectionManager

    var body: some View {
        Form {
            Section("Apple Intelligence") {
                Toggle(
                    "Improve transcriptions with the on-device model",
                    isOn: $store.enableLocalCorrection
                )

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: statusSymbol)
                        .foregroundStyle(statusColor)
                        .font(.title3)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(correctionManager.availability.title)
                            .font(.headline)
                        Text(correctionManager.availability.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                HStack {
                    Button {
                        correctionManager.refreshAvailability()
                    } label: {
                        Label("Refresh Status", systemImage: "arrow.clockwise")
                    }

                    if shouldOfferAppleIntelligenceSettings {
                        Button("Open System Settings") {
                            correctionManager.openAppleIntelligenceSettings()
                        }
                    }
                }
            }

            Section("Session Context") {
                LabeledContent(
                    "Current context",
                    value: "\(correctionManager.contextFragmentCount) / \(6) fragments"
                )

                Text("Parrot keeps at most six recent fragments (approximately 800–1000 tokens) only in RAM. It expires after three minutes, resets when you dictate into another app, and is deleted when Parrot quits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    correctionManager.clearContext()
                } label: {
                    Label("New Context", systemImage: "arrow.counterclockwise")
                }
            }

            Section("Battery and Reliability") {
                Label(
                    "Runs only once after each dictation",
                    systemImage: "waveform.badge.magnifyingglass"
                )
                Label(
                    "Automatically skipped in Low Power Mode",
                    systemImage: "battery.25percent"
                )
                Label(
                    "Falls back to the original text after a 4-second timeout or any error",
                    systemImage: "arrow.uturn.backward.circle"
                )

                Text("No cloud service, network request, background processing, transcript history, or persistent LLM session is used.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            correctionManager.refreshAvailability()
        }
    }

    private var shouldOfferAppleIntelligenceSettings: Bool {
        switch correctionManager.availability {
        case .appleIntelligenceNotEnabled, .modelNotReady:
            return true
        default:
            return false
        }
    }

    private var statusSymbol: String {
        switch correctionManager.availability {
        case .available:
            return "checkmark.circle.fill"
        case .modelNotReady:
            return "clock.fill"
        default:
            return "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch correctionManager.availability {
        case .available:
            return .green
        case .modelNotReady:
            return .orange
        default:
            return .red
        }
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var store: SettingsStore
    let activeModel: TranscriptionModel
    let modelIsOverridden: Bool
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
                Picker("Default model", selection: $store.selectedModelID) {
                    ForEach(ModelRegistry.shared, id: \.id) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }

                LabeledContent("Active now", value: activeModel.displayName)
                LabeledContent(
                    "Selected language",
                    value: selectedModel?.languageMode.displayName ?? "Unknown"
                )
                LabeledContent(
                    "Selected download size",
                    value: selectedModel.map { "\($0.sizeMB) MB" } ?? "Unknown"
                )

                if modelIsOverridden {
                    Text("The --model command-line option overrides the saved model for this run.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if store.selectedModelID != activeModel.id {
                    Text("Restart Parrot to load the newly selected model.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if activeModel.languageMode == .automatic {
                    Text("Language is detected independently for each dictation. Spanish is the primary target; English utterances and occasional English terms remain supported.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("Restore Defaults") {
                        store.resetGeneralSettings()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var selectedModel: TranscriptionModel? {
        ModelRegistry.find(store.selectedModelID)
    }
}

private struct DictionarySettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Custom replacements")
                    .font(.title3.weight(.semibold))
                Text("Replace words or phrases after transcription and before Parrot types them.")
                    .foregroundStyle(.secondary)
            }

            if store.replacementRules.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "character.book.closed")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No replacements yet")
                        .font(.headline)
                    Text("For example: “te paso mi mail” → “name@example.com”")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 10) {
                    Text("When the transcript contains")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Replace it with")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(width: 24)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach($store.replacementRules) { $rule in
                            HStack(spacing: 10) {
                                TextField("Spoken word or phrase", text: $rule.spokenPhrase)
                                    .textFieldStyle(.roundedBorder)
                                Image(systemName: "arrow.right")
                                    .foregroundStyle(.secondary)
                                TextField("Text to type", text: $rule.replacement)
                                    .textFieldStyle(.roundedBorder)
                                Button {
                                    store.removeReplacementRule(id: rule.id)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.red)
                                .help("Remove replacement")
                            }
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button {
                    store.addReplacementRule()
                } label: {
                    Label("Add Replacement", systemImage: "plus")
                }
                Spacer()
                Text("Stored only in local app preferences.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(22)
    }
}

private struct PermissionsSettingsView: View {
    @ObservedObject var permissionManager: PermissionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Permissions")
                    .font(.title3.weight(.semibold))
                Text("Parrot needs both permissions for global dictation and text injection.")
                    .foregroundStyle(.secondary)
            }

            PermissionRow(
                title: "Microphone",
                granted: permissionManager.microphoneGranted,
                detail: microphoneDetail,
                actionTitle: microphoneActionTitle,
                action: microphoneAction
            )

            PermissionRow(
                title: "Accessibility",
                granted: permissionManager.accessibilityGranted,
                detail: permissionManager.accessibilityGranted
                    ? "Global shortcut and text injection are enabled."
                    : "Required to detect the shortcut and type at the cursor.",
                actionTitle: permissionManager.accessibilityGranted ? nil : "Open Settings",
                action: permissionManager.openAccessibilitySettings
            )

            Spacer()

            HStack {
                Button {
                    permissionManager.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Spacer()
                Text("After changing System Settings, return here and refresh.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .onAppear {
            permissionManager.refresh()
        }
    }

    private var microphoneDetail: String {
        switch permissionManager.microphoneStatus {
        case .authorized:
            return "Audio capture is enabled while dictation is active."
        case .notDetermined:
            return "macOS has not asked for microphone access yet."
        case .denied:
            return "Microphone access was denied in System Settings."
        case .restricted:
            return "Microphone access is restricted on this Mac."
        @unknown default:
            return "The microphone permission state is unknown."
        }
    }

    private var microphoneActionTitle: String? {
        switch permissionManager.microphoneStatus {
        case .authorized:
            return nil
        case .notDetermined:
            return "Request Access"
        case .denied, .restricted:
            return "Open Settings"
        @unknown default:
            return "Open Settings"
        }
    }

    private var microphoneAction: () -> Void {
        permissionManager.microphoneStatus == .notDetermined
            ? permissionManager.requestMicrophone
            : permissionManager.openMicrophoneSettings
    }
}

private struct PermissionRow: View {
    let title: String
    let granted: Bool
    let detail: String
    let actionTitle: String?
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(granted ? .green : .red)
                .accessibilityLabel(granted ? "Granted" : "Not granted")

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let actionTitle {
                Button(actionTitle, action: action)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
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
