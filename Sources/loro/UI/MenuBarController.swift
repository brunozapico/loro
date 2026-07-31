import AppKit
import LoroCore

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
    private let onClearContext: () -> Void
    private var shortcut: HotkeyShortcut
    private var dictationMode: DictationMode
    private var state: State = .idle
    private var recordingFrame = -1
    private var transcribingFrame = 0
    private var transcribingTimer: Timer?
    private lazy var recordingImages = (0..<3).map { Self.recordingBirdImage(frame: $0) }
    private lazy var transcribingImages = (0..<3).map { Self.transcribingBirdImage(frame: $0) }

    init(
        modelID: String,
        settings: AppSettings,
        onOpenSettings: @escaping () -> Void,
        onClearContext: @escaping () -> Void
    ) {
        self.modelID = modelID
        self.shortcut = settings.shortcut
        self.dictationMode = settings.dictationMode
        self.onOpenSettings = onOpenSettings
        self.onClearContext = onClearContext
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

        let newContextItem = NSMenuItem(
            title: "New Context",
            action: #selector(newContextClicked),
            keyEquivalent: ""
        )
        newContextItem.target = self
        menu.addItem(newContextItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit Loro",
            action: #selector(quitClicked),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        updateIdleLabel()
        configureButton()
    }

    func setRecording(_ recording: Bool) {
        stopTranscribingAnimation()
        if recording {
            state = .recording
            stateLabel.title = "● recording"
            recordingFrame = -1
            updateAudioLevel(0)
        } else {
            state = .idle
            recordingFrame = -1
            updateIdleLabel()
            setButtonImage(Self.birdImage())
        }
    }

    func setTranscribing() {
        state = .transcribing
        stateLabel.title = "transcribing…"
        recordingFrame = -1
        startTranscribingAnimation()
    }

    func setError(_ message: String) {
        stopTranscribingAnimation()
        state = .error
        stateLabel.title = message
        setButtonImage(Self.birdImage())
    }

    func updateAudioLevel(_ level: Float) {
        guard state == .recording else { return }

        let frame = MenuBarAnimation.recordingFrame(for: level)
        guard frame != recordingFrame else { return }

        recordingFrame = frame
        setButtonImage(recordingImages[frame])
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

    private func configureButton() {
        setButtonImage(Self.birdImage())
    }

    private func setButtonImage(_ image: NSImage?) {
        guard let button = statusItem.button else { return }

        if let image {
            image.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.title = ""
        } else {
            button.image = nil
            button.title = "L"
        }
    }

    private func startTranscribingAnimation() {
        stopTranscribingAnimation()
        transcribingFrame = 0
        setButtonImage(transcribingImages[transcribingFrame])

        let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.state == .transcribing else { return }
                self.transcribingFrame = MenuBarAnimation.nextDotsFrame(after: self.transcribingFrame)
                self.setButtonImage(self.transcribingImages[self.transcribingFrame])
            }
        }
        transcribingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopTranscribingAnimation() {
        transcribingTimer?.invalidate()
        transcribingTimer = nil
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
        image(from: birdSVG, size: NSSize(width: 16, height: 16))
    }

    private static func recordingBirdImage(frame: Int) -> NSImage? {
        let waves: String
        switch frame {
        case 2:
            waves = """
            <path d="M24 6.2c.8.7.8 1.9 0 2.6"/>
            <path d="M26.4 4.8c1.7 1.5 1.7 4 0 5.5"/>
            <path d="M29 3.3c2.5 2.2 2.5 6.3 0 8.5"/>
            """
        case 1:
            waves = """
            <path d="M24 6.2c.8.7.8 1.9 0 2.6"/>
            <path d="M26.4 4.8c1.7 1.5 1.7 4 0 5.5" opacity=".7"/>
            """
        default:
            waves = """
            <path d="M24 6.2c.8.7.8 1.9 0 2.6" opacity=".45"/>
            <path d="M26.4 4.8c1.7 1.5 1.7 4 0 5.5" opacity=".22"/>
            """
        }

        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="32" height="24" viewBox="0 0 32 24"
             fill="none" stroke="currentColor" stroke-width="1.5"
             stroke-linecap="round" stroke-linejoin="round">
          \(birdPaths)
          \(waves)
        </svg>
        """
        return image(from: svg, size: NSSize(width: 22, height: 16))
    }

    private static func transcribingBirdImage(frame: Int) -> NSImage? {
        let opacities = (0..<3).map { $0 == frame ? "1" : ".25" }
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="24" height="28" viewBox="0 0 24 28"
             fill="none" stroke="currentColor" stroke-width="1.5"
             stroke-linecap="round" stroke-linejoin="round">
          \(birdPaths)
          <g fill="currentColor" stroke="none">
            <circle cx="8" cy="25" r="1" opacity="\(opacities[0])"/>
            <circle cx="12" cy="25" r="1" opacity="\(opacities[1])"/>
            <circle cx="16" cy="25" r="1" opacity="\(opacities[2])"/>
          </g>
        </svg>
        """
        return image(from: svg, size: NSSize(width: 16, height: 18))
    }

    private static func image(from svg: String, size: NSSize) -> NSImage? {
        guard let data = svg.data(using: .utf8),
              let image = NSImage(data: data)
        else { return nil }
        image.size = size
        image.isTemplate = true
        return image
    }

    private static let birdPaths = """
      <path d="M16 7h.01"/>
      <path d="M3.4 18H12a8 8 0 0 0 8-8V7a4 4 0 0 0-7.28-2.3L2 20"/>
      <path d="m20 7 2 .5-2 .5"/>
      <path d="M10 18v3"/>
      <path d="M14 17.75V21"/>
      <path d="M7 18a6 6 0 0 0 3.84-10.61"/>
    """

    @objc private func settingsClicked() {
        onOpenSettings()
    }

    @objc private func newContextClicked() {
        onClearContext()
    }

    @objc private func quitClicked() {
        onClearContext()
        NSApp.terminate(nil)
    }
}
