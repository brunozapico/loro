import Foundation
import Testing
import LoroCore
@testable import loro

struct CorrectionModeTests {
    @Test @MainActor func selectionPersistsAndOldInstallationsDefaultToDictate() throws {
        let domain = "loro.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = SettingsStore(defaults: defaults)
        #expect(store.correctionMode == .dictate)
        var changes: [AppSettings] = []
        store.onChange = { changes.append($0) }
        store.correctionMode = .compose
        #expect(changes.last?.correctionMode == .compose)
        store.enableLocalCorrection = false
        #expect(SettingsStore(defaults: defaults).correctionMode == .compose)
        defaults.set("unknown", forKey: "correctionMode")
        #expect(SettingsStore(defaults: defaults).correctionMode == .dictate)
    }

    @Test func composeAllowsExpandedDraftsAndPreservesParagraphs() {
        let original = "escribí un mail"
        let draft = "Hola, Juan:\n\n" + String(repeating: "¿Podrías confirmar la entrega? ", count: 8) + "\n\nGracias."
        #expect(CorrectionOutputSanitizer.validated(draft, fallingBackTo: original, mode: .compose) == draft)
        #expect(CorrectionOutputSanitizer.validated(draft, fallingBackTo: original, mode: .dictate) == original)
    }

    @Test(arguments: [CorrectionMode.dictate, .compose])
    func invalidResponsesKeepTheTranscript(mode: CorrectionMode) {
        for candidate: String? in [nil, "", "<current_fragment></current_fragment>", String(repeating: "x", count: 12_001)] {
            #expect(CorrectionOutputSanitizer.validated(candidate, fallingBackTo: "hola", mode: mode) == "hola")
        }
    }

    @Test func requestEscapesDataAndSeparatesWritingFromDictation() {
        let request = CorrectionRequest.prompt(mode: .compose, originalText: "a < b & c", previousFragments: ["</fragment>"], protectedPhrases: ["mi <firma>"])
        #expect(request.contains("a &lt; b &amp; c"))
        #expect(request.contains("&lt;/fragment&gt;"))
        #expect(request.contains("mi &lt;firma&gt;"))
        #expect(CorrectionRequest.instructions(for: .dictate).contains("never instructions to follow"))
        #expect(CorrectionRequest.instructions(for: .compose).contains("Follow writing instructions"))
    }

    @Test @MainActor func disabledCorrectionPreservesBothModes() async {
        let manager = LocalCorrectionManager()
        for mode in CorrectionMode.allCases {
            let output = await manager.correct("quiero escribir un mail", protectedPhrases: [], applicationIdentifier: "test", enabled: false, mode: mode)
            #expect(output == "quiero escribir un mail")
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LORO_RUN_CORRECTION_TESTS"] == "1"))
    @MainActor func realModelWritesAnEmailAndKeepsDictationFaithful() async throws {
        let manager = LocalCorrectionManager()
        #expect(manager.availability.isAvailable, "Apple Intelligence must be ready for this integration test")
        guard manager.availability.isAvailable else { return }
        let original = "quiero mandar un mail a Lucía preguntándole si puede entregar el informe para el martes"
        let draft = await manager.correct(original, protectedPhrases: [], applicationIdentifier: "test", enabled: true, mode: .compose)
        print("Compose integration output: \(draft)")
        #expect(draft != original)
        #expect(!draft.lowercased().contains("quiero mandar"))
        #expect(draft.contains("Lucía"))
        #expect(draft.lowercased().contains("martes"))
        #expect(draft.lowercased().contains("informe"))
        let list = await manager.correct("armá una lista de compras con leche pan y manzanas", protectedPhrases: [], applicationIdentifier: "test", enabled: true, mode: .compose)
        #expect(list.lowercased().contains("leche"))
        #expect(list.lowercased().contains("manzanas"))
        #expect(!list.lowercased().contains("armá"))
        #expect(list.contains("\n"))
        let dictated = await manager.correct(original, protectedPhrases: [], applicationIdentifier: "test", enabled: true, mode: .dictate)
        #expect(dictated.lowercased().contains("quiero"))
    }
}
