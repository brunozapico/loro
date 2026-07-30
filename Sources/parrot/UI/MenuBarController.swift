import AppKit

/// Status bar item in the top-right of the menu bar. Shows recording state at
/// a glance and provides the only persistent control surface for the daemon
/// (since we run as `.accessory` — no dock icon, no main window).
@MainActor
final class MenuBarController {
    private enum State {
        case idle
        case recording
        case transcribing
        case error
    }

    private let statusItem: NSStatusItem
    private let modelLabel: NSMenuItem
    private let stateLabel: NSMenuItem
    private let modelID: String
    private let onOpenSettings: () -> Void
    private var shortcut: HotkeyShortcut
    private var dictationMode: DictationMode
    private var state: State = .idle

    init(modelID: String, settings: AppSettings, onOpenSettings: @escaping () -> Void) {
        self.modelID = modelID
        self.shortcut = settings.shortcut
        self.dictationMode = settings.dictationMode
        self.onOpenSettings = onOpenSettings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.autoenablesItems = false

        stateLabel = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        stateLabel.isEnabled = false
        menu.addItem(stateLabel)

        modelLabel = NSMenuItem(title: "model: \(modelID)", action: nil, keyEquivalent: "")
        modelLabel.isEnabled = false
        menu.addItem(modelLabel)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(settingsClicked),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quit = NSMenuItem(
            title: "Quit parrot",
            action: #selector(quitClicked),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        updateIdleLabel()
        configureButton(recording: false)
    }

    func setRecording(_ recording: Bool) {
        if recording {
            state = .recording
            stateLabel.title = "● recording"
        } else {
            state = .idle
            updateIdleLabel()
        }
    }

    func setTranscribing() {
        state = .transcribing
        stateLabel.title = "transcribing…"
    }

    func setError(_ message: String) {
        state = .error
        stateLabel.title = message
    }

    func apply(_ settings: AppSettings) {
        shortcut = settings.shortcut
        dictationMode = settings.dictationMode
        if state == .idle {
            updateIdleLabel()
        }
    }

    private func updateIdleLabel() {
        let action = dictationMode == .pushToTalk ? "hold" : "press"
        stateLabel.title = "idle · \(action) \(shortcut.displayName) to dictate"
    }

    private func configureButton(recording: Bool) {
        guard let button = statusItem.button else { return }
        let image = Self.birdImage()
        image?.isTemplate = true
        button.image = image
    }

    // Inlined Lucide bird SVG. Keeping it in source means the executable has
    // no separate resource bundle to install alongside it — true single-binary.
    private static let birdSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" \
    viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" \
    stroke-linecap="round" stroke-linejoin="round">\
    <path d="M16 7h.01"/>\
    <path d="M3.4 18H12a8 8 0 0 0 8-8V7a4 4 0 0 0-7.28-2.3L2 20"/>\
    <path d="m20 7 2 .5-2 .5"/>\
    <path d="M10 18v3"/>\
    <path d="M14 17.75V21"/>\
    <path d="M7 18a6 6 0 0 0 3.84-10.61"/>\
    </svg>
    """

    private static func birdImage() -> NSImage? {
        guard let data = birdSVG.data(using: .utf8),
              let image = NSImage(data: data)
        else { return nil }
        // Menu-bar status icons are nominally 18pt tall; size the SVG to match.
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    @objc private func settingsClicked() {
        onOpenSettings()
    }

    @objc private func quitClicked() {
        NSApp.terminate(nil)
    }
}
