import Testing
@testable import LoroCore

final class CorrectionOutputSanitizerTests {
    private let original = "esto es una locura nunca mas en mi vida vuelvo a escribir"
    private let corrected = "Esto es una locura. Nunca más en mi vida vuelvo a escribir."

    @Test func testRemovesCorrectedFragmentWrapperFromReportedRegression() {
        let response = """
        <corrected_fragment>Esto es una locura. Nunca más en mi vida vuelvo a escribir, o sea, \
        hablas mucho más rápido de lo que escribís.</corrected_fragment>
        """

        #expect(CorrectionOutputSanitizer.validated(response, fallingBackTo: original) == "Esto es una locura. Nunca más en mi vida vuelvo a escribir, o sea, "
                + "hablas mucho más rápido de lo que escribís.")
    }

    @Test func testRemovesCaseInsensitiveAndSpacedWrapper() {
        let response = """
        < Corrected_Fragment >
        \(corrected)
        </ Corrected_Fragment >
        """

        #expect(CorrectionOutputSanitizer.validated(response, fallingBackTo: original) == corrected)
    }

    @Test func testRemovesWrapperInsideMarkdownFence() {
        let response = """
        ```xml
        <corrected_fragment>\(corrected)</corrected_fragment>
        ```
        """

        #expect(CorrectionOutputSanitizer.validated(response, fallingBackTo: original) == corrected)
    }

    @Test func testRemovesEscapedWrapper() {
        let response =
            "&lt;corrected_fragment&gt;\(corrected)&lt;/corrected_fragment&gt;"

        #expect(CorrectionOutputSanitizer.validated(response, fallingBackTo: original) == corrected)
    }

    @Test func testRemovesPlainControlLabel() {
        let response = "Corrected fragment: \(corrected)"

        #expect(CorrectionOutputSanitizer.validated(response, fallingBackTo: original) == corrected)
    }

    @Test func testRejectsResidualControlMarker() {
        let response = "\(corrected) corrected_fragment"

        #expect(CorrectionOutputSanitizer.validated(response, fallingBackTo: original) == original)
    }

    @Test func testSanitizesControlTagsFromFallback() {
        let taggedOriginal = "<corrected_fragment>\(original)</corrected_fragment>"

        #expect(CorrectionOutputSanitizer.validated(nil, fallingBackTo: taggedOriginal) == original)
    }

    @Test func testPreservesOrdinaryMixedLanguageText() {
        let response = "Hola Juan, te paso el meeting link en un minuto."

        #expect(CorrectionOutputSanitizer.validated(response, fallingBackTo: original) == response)
    }
}
