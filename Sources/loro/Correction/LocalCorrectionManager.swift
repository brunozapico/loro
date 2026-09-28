import AppKit
import Combine
import Foundation
import LoroCore

#if canImport(FoundationModels)
import FoundationModels
#endif

#if LORO_RELEASE_REQUIRES_FOUNDATION_MODELS && !canImport(FoundationModels)
#error("Release builds require the macOS 26 SDK and FoundationModels framework")
#endif

enum LocalCorrectionAvailability: Equatable {
    case available
    case unsupportedOS
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady

    var isAvailable: Bool {
        self == .available
    }

    var title: String {
        switch self {
        case .available:
            return "Ready"
        case .unsupportedOS:
            return "Requires macOS 26 or later"
        case .deviceNotEligible:
            return "This Mac is not eligible"
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is not enabled"
        case .modelNotReady:
            return "The on-device model is not ready"
        }
    }

    var detail: String {
        switch self {
        case .available:
            return "Corrections run with Apple Foundation Models entirely on this Mac."
        case .unsupportedOS:
            return "Loro will use the original transcription without LLM correction."
        case .deviceNotEligible:
            return "Loro will use the original transcription without LLM correction."
        case .appleIntelligenceNotEnabled:
            return "Enable Apple Intelligence in System Settings, then refresh this status."
        case .modelNotReady:
            return "Apple Intelligence may still be downloading or preparing its local model."
        }
    }
}

struct CorrectionContextSnapshot: Sendable {
    let fragments: [String]
}

/// Volatile conversation context. Nothing in this actor is encoded, logged, or
/// written to disk, and the actor is discarded with the Loro process.
actor CorrectionContextStore {
    private struct Entry {
        let text: String
        let date: Date
    }

    static let maximumFragments = 6
    static let maximumCharacters = 3_600
    static let expirationInterval: TimeInterval = 3 * 60

    private var entries: [Entry] = []
    private var applicationIdentifier: String?

    func snapshot(for application: String, now: Date = Date()) -> CorrectionContextSnapshot {
        resetIfNeeded(for: application, now: now)
        return CorrectionContextSnapshot(fragments: entries.map(\.text))
    }

    func append(_ text: String, for application: String, now: Date = Date()) -> Int {
        resetIfNeeded(for: application, now: now)

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries.count }

        entries.append(Entry(text: trimmed, date: now))
        while entries.count > Self.maximumFragments || characterCount > Self.maximumCharacters {
            entries.removeFirst()
        }
        return entries.count
    }

    func clear() {
        entries.removeAll(keepingCapacity: false)
        applicationIdentifier = nil
    }

    private var characterCount: Int {
        entries.reduce(0) { $0 + $1.text.count }
    }

    private func resetIfNeeded(for application: String, now: Date) {
        let appChanged = applicationIdentifier.map { $0 != application } ?? false
        let expired = entries.last.map {
            now.timeIntervalSince($0.date) >= Self.expirationInterval
        } ?? false

        if appChanged || expired {
            entries.removeAll(keepingCapacity: false)
        }
        applicationIdentifier = application
    }
}

@MainActor
final class LocalCorrectionManager: ObservableObject {
    @Published private(set) var availability: LocalCorrectionAvailability = .unsupportedOS
    @Published private(set) var contextFragmentCount = 0

    private let isLowPowerModeEnabled: () -> Bool
    private let contextStore = CorrectionContextStore()
    private static let correctionOperation = TimedOperation<String>()

    init(isLowPowerModeEnabled: @escaping () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled }) {
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
        refreshAvailability()
    }

    func refreshAvailability() {
        availability = Self.currentAvailability()
    }

    func correct(
        _ originalText: String,
        protectedPhrases: [String],
        applicationIdentifier: String,
        enabled: Bool,
        mode: CorrectionMode = .dictate
    ) async -> String {
        refreshAvailability()

        guard enabled,
              availability.isAvailable,
              !isLowPowerModeEnabled()
        else {
            return originalText
        }

        let snapshot = await contextStore.snapshot(for: "\(mode.rawValue):\(applicationIdentifier)")
        contextFragmentCount = snapshot.fragments.count

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let result = await Self.runFoundationModel(
                originalText: originalText,
                previousFragments: snapshot.fragments,
                protectedPhrases: protectedPhrases,
                mode: mode
            )
            return CorrectionOutputSanitizer.validated(
                result,
                fallingBackTo: originalText,
                mode: mode
            )
        }
        #endif

        return originalText
    }

    func remember(_ finalText: String, applicationIdentifier: String, enabled: Bool, mode: CorrectionMode = .dictate) async {
        guard enabled else { return }
        contextFragmentCount = await contextStore.append(
            finalText,
            for: "\(mode.rawValue):\(applicationIdentifier)"
        )
    }

    func clearContext() {
        contextFragmentCount = 0
        Task {
            await contextStore.clear()
        }
    }

    func openAppleIntelligenceSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Siri-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private static func currentAvailability() -> LocalCorrectionAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(.deviceNotEligible):
                return .deviceNotEligible
            case .unavailable(.appleIntelligenceNotEnabled):
                return .appleIntelligenceNotEnabled
            case .unavailable(.modelNotReady):
                return .modelNotReady
            @unknown default:
                return .modelNotReady
            }
        }
        #endif

        return .unsupportedOS
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func runFoundationModel(
        originalText: String,
        previousFragments: [String],
        protectedPhrases: [String],
        mode: CorrectionMode
    ) async -> String? {
        let instructions = CorrectionRequest.instructions(for: mode)
        let prompt = CorrectionRequest.prompt(
            mode: mode,
            originalText: originalText,
            previousFragments: previousFragments,
            protectedPhrases: protectedPhrases
        )
        let timeout = UInt64(mode.timeoutSeconds) * 1_000_000_000

        return try? await correctionOperation.run(timeoutNanoseconds: timeout) {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt)
            return response.content
        }
    }

    #endif
}
