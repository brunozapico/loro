import AppKit
import Combine
import CoreGraphics
import Foundation

enum DictationMode: String, Codable, CaseIterable, Identifiable {
    case pushToTalk
    case toggle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pushToTalk: return "Push to Talk"
        case .toggle: return "Toggle"
        }
    }

    var helpText: String {
        switch self {
        case .pushToTalk:
            return "Hold the shortcut while speaking, then release it to transcribe."
        case .toggle:
            return "Press once to start recording and again to stop and transcribe."
        }
    }
}

struct HotkeyShortcut: Codable, Equatable {
    let keyCode: UInt16?
    let modifiers: UInt64
    let keyLabel: String

    static let functionKey = HotkeyShortcut(
        keyCode: nil,
        modifiers: CGEventFlags.maskSecondaryFn.rawValue,
        keyLabel: ""
    )

    var isModifierOnly: Bool { keyCode == nil }

    var displayName: String {
        let flags = CGEventFlags(rawValue: modifiers)
        var parts: [String] = []
        if flags.contains(.maskControl) { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift) { parts.append("⇧") }
        if flags.contains(.maskCommand) { parts.append("⌘") }
        if flags.contains(.maskSecondaryFn) { parts.append("fn") }
        if !keyLabel.isEmpty { parts.append(keyLabel.uppercased()) }
        return parts.isEmpty ? "Not set" : parts.joined()
    }

    func matchesModifiers(_ eventFlags: CGEventFlags) -> Bool {
        Self.normalized(eventFlags) == modifiers
    }

    func containsModifiers(_ eventFlags: CGEventFlags) -> Bool {
        let normalized = Self.normalized(eventFlags)
        return normalized & modifiers == modifiers
    }

    static func normalized(_ flags: CGEventFlags) -> UInt64 {
        flags.rawValue & supportedModifierMask.rawValue
    }

    static func normalized(_ flags: NSEvent.ModifierFlags) -> UInt64 {
        normalized(CGEventFlags(rawValue: UInt64(flags.rawValue)))
    }

    static let supportedModifierMask: CGEventFlags = [
        .maskControl,
        .maskAlternate,
        .maskShift,
        .maskCommand,
        .maskSecondaryFn,
    ]
}

struct AppSettings: Equatable {
    var shortcut: HotkeyShortcut
    var dictationMode: DictationMode
    var showOverlay: Bool
    var copyToClipboard: Bool
    var stopOnSilence: Bool
    var silenceTimeoutSeconds: Int
    var enableLocalCorrection: Bool
    var selectedModelID: String
    var replacementRules: [ReplacementRule]
}

@MainActor
final class SettingsStore: ObservableObject {
    static let defaultSilenceTimeoutSeconds = 5
    static let silenceTimeoutRange = 2...30

    private static let suiteName = "com.brunozapico.loro"
    private static let legacySuiteName = "com.digimata.parrot"

    private enum Key {
        static let shortcut = "shortcut"
        static let dictationMode = "dictationMode"
        static let showOverlay = "showOverlay"
        static let copyToClipboard = "copyToClipboard"
        static let stopOnSilence = "stopOnSilence"
        static let silenceTimeoutSeconds = "silenceTimeoutSeconds"
        static let enableLocalCorrection = "enableLocalCorrection"
        static let selectedModelID = "selectedModelID"
        static let replacementRules = "replacementRules"
    }

    private let defaults: UserDefaults
    var onChange: ((AppSettings) -> Void)?

    @Published var shortcut: HotkeyShortcut {
        didSet {
            guard shortcut != oldValue else { return }
            persistShortcut()
            notifyChange()
        }
    }

    @Published var dictationMode: DictationMode {
        didSet {
            guard dictationMode != oldValue else { return }
            defaults.set(dictationMode.rawValue, forKey: Key.dictationMode)
            notifyChange()
        }
    }

    @Published var showOverlay: Bool {
        didSet {
            guard showOverlay != oldValue else { return }
            defaults.set(showOverlay, forKey: Key.showOverlay)
            notifyChange()
        }
    }

    @Published var copyToClipboard: Bool {
        didSet {
            guard copyToClipboard != oldValue else { return }
            defaults.set(copyToClipboard, forKey: Key.copyToClipboard)
            notifyChange()
        }
    }

    @Published var stopOnSilence: Bool {
        didSet {
            guard stopOnSilence != oldValue else { return }
            defaults.set(stopOnSilence, forKey: Key.stopOnSilence)
            notifyChange()
        }
    }

    @Published var silenceTimeoutSeconds: Int {
        didSet {
            let clamped = Self.silenceTimeoutRange.clamped(silenceTimeoutSeconds)
            if clamped != silenceTimeoutSeconds {
                silenceTimeoutSeconds = clamped
                return
            }
            guard silenceTimeoutSeconds != oldValue else { return }
            defaults.set(silenceTimeoutSeconds, forKey: Key.silenceTimeoutSeconds)
            notifyChange()
        }
    }

    @Published var enableLocalCorrection: Bool {
        didSet {
            guard enableLocalCorrection != oldValue else { return }
            defaults.set(enableLocalCorrection, forKey: Key.enableLocalCorrection)
            notifyChange()
        }
    }

    @Published var selectedModelID: String {
        didSet {
            guard selectedModelID != oldValue else { return }
            defaults.set(selectedModelID, forKey: Key.selectedModelID)
            notifyChange()
        }
    }

    @Published var replacementRules: [ReplacementRule] {
        didSet {
            guard replacementRules != oldValue else { return }
            persistReplacementRules()
            notifyChange()
        }
    }

    init(defaults: UserDefaults? = nil) {
        let defaults = defaults ?? Self.makeDefaults()
        self.defaults = defaults

        if
            let data = defaults.data(forKey: Key.shortcut),
            let decoded = try? JSONDecoder().decode(HotkeyShortcut.self, from: data)
        {
            shortcut = decoded
        } else {
            shortcut = .functionKey
        }

        if
            let rawMode = defaults.string(forKey: Key.dictationMode),
            let mode = DictationMode(rawValue: rawMode)
        {
            dictationMode = mode
        } else {
            dictationMode = .pushToTalk
        }

        if defaults.object(forKey: Key.showOverlay) == nil {
            showOverlay = true
        } else {
            showOverlay = defaults.bool(forKey: Key.showOverlay)
        }

        if defaults.object(forKey: Key.copyToClipboard) == nil {
            copyToClipboard = true
        } else {
            copyToClipboard = defaults.bool(forKey: Key.copyToClipboard)
        }

        if defaults.object(forKey: Key.stopOnSilence) == nil {
            stopOnSilence = true
        } else {
            stopOnSilence = defaults.bool(forKey: Key.stopOnSilence)
        }

        if defaults.object(forKey: Key.silenceTimeoutSeconds) == nil {
            silenceTimeoutSeconds = Self.defaultSilenceTimeoutSeconds
        } else {
            silenceTimeoutSeconds = Self.silenceTimeoutRange.clamped(
                defaults.integer(forKey: Key.silenceTimeoutSeconds)
            )
        }

        if defaults.object(forKey: Key.enableLocalCorrection) == nil {
            enableLocalCorrection = true
        } else {
            enableLocalCorrection = defaults.bool(forKey: Key.enableLocalCorrection)
        }

        if
            let storedModelID = defaults.string(forKey: Key.selectedModelID),
            ModelRegistry.find(storedModelID) != nil
        {
            selectedModelID = storedModelID
        } else {
            selectedModelID = ModelRegistry.recommended()?.id ?? ""
        }

        if
            let data = defaults.data(forKey: Key.replacementRules),
            let decoded = try? JSONDecoder().decode([ReplacementRule].self, from: data)
        {
            replacementRules = decoded
        } else {
            replacementRules = []
        }
    }

    var current: AppSettings {
        AppSettings(
            shortcut: shortcut,
            dictationMode: dictationMode,
            showOverlay: showOverlay,
            copyToClipboard: copyToClipboard,
            stopOnSilence: stopOnSilence,
            silenceTimeoutSeconds: silenceTimeoutSeconds,
            enableLocalCorrection: enableLocalCorrection,
            selectedModelID: selectedModelID,
            replacementRules: replacementRules
        )
    }

    func resetGeneralSettings() {
        shortcut = .functionKey
        dictationMode = .pushToTalk
        showOverlay = true
        copyToClipboard = true
        stopOnSilence = true
        silenceTimeoutSeconds = Self.defaultSilenceTimeoutSeconds
        selectedModelID = ModelRegistry.recommended()?.id ?? ""
    }

    func addReplacementRule() {
        replacementRules.append(ReplacementRule())
    }

    func removeReplacementRule(id: ReplacementRule.ID) {
        replacementRules.removeAll { $0.id == id }
    }

    private func persistShortcut() {
        if let data = try? JSONEncoder().encode(shortcut) {
            defaults.set(data, forKey: Key.shortcut)
        }
    }

    private func persistReplacementRules() {
        if let data = try? JSONEncoder().encode(replacementRules) {
            defaults.set(data, forKey: Key.replacementRules)
        }
    }

    private func notifyChange() {
        onChange?(current)
    }

    private static func makeDefaults() -> UserDefaults {
        let standard = UserDefaults.standard
        let currentDomain = standard.persistentDomain(forName: suiteName)
        if
            currentDomain?.isEmpty != false,
            let legacyDomain = standard.persistentDomain(forName: legacySuiteName),
            !legacyDomain.isEmpty
        {
            standard.setPersistentDomain(legacyDomain, forName: suiteName)
        }
        return UserDefaults(suiteName: suiteName)!
    }
}

private extension ClosedRange where Bound == Int {
    func clamped(_ value: Int) -> Int {
        min(max(value, lowerBound), upperBound)
    }
}
