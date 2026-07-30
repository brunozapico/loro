import XCTest
@testable import LoroCore

final class CorrectionOutputSanitizerTests: XCTestCase {
    private let original = "esto es una locura nunca mas en mi vida vuelvo a escribir"
    private let corrected = "Esto es una locura. Nunca más en mi vida vuelvo a escribir."

    func testRemovesCorrectedFragmentWrapperFromReportedRegression() {
        let response = """
        <corrected_fragment>Esto es una locura. Nunca más en mi vida vuelvo a escribir, o sea, \
        hablas mucho más rápido de lo que escribís.</corrected_fragment>
        """

        XCTAssertEqual(
            CorrectionOutputSanitizer.validated(response, fallingBackTo: original),
            "Esto es una locura. Nunca más en mi vida vuelvo a escribir, o sea, "
                + "hablas mucho más rápido de lo que escribís."
        )
    }

    func testRemovesCaseInsensitiveAndSpacedWrapper() {
        let response = """
        < Corrected_Fragment >
        \(corrected)
        </ Corrected_Fragment >
        """

        XCTAssertEqual(
            CorrectionOutputSanitizer.validated(response, fallingBackTo: original),
            corrected
        )
    }

    func testRemovesWrapperInsideMarkdownFence() {
        let response = """
        ```xml
        <corrected_fragment>\(corrected)</corrected_fragment>
        ```
        """

        XCTAssertEqual(
            CorrectionOutputSanitizer.validated(response, fallingBackTo: original),
            corrected
        )
    }

    func testRemovesEscapedWrapper() {
        let response =
            "&lt;corrected_fragment&gt;\(corrected)&lt;/corrected_fragment&gt;"

        XCTAssertEqual(
            CorrectionOutputSanitizer.validated(response, fallingBackTo: original),
            corrected
        )
    }

    func testRemovesPlainControlLabel() {
        let response = "Corrected fragment: \(corrected)"

        XCTAssertEqual(
            CorrectionOutputSanitizer.validated(response, fallingBackTo: original),
            corrected
        )
    }

    func testRejectsResidualControlMarker() {
        let response = "\(corrected) corrected_fragment"

        XCTAssertEqual(
            CorrectionOutputSanitizer.validated(response, fallingBackTo: original),
            original
        )
    }

    func testSanitizesControlTagsFromFallback() {
        let taggedOriginal = "<corrected_fragment>\(original)</corrected_fragment>"

        XCTAssertEqual(
            CorrectionOutputSanitizer.validated(nil, fallingBackTo: taggedOriginal),
            original
        )
    }

    func testPreservesOrdinaryMixedLanguageText() {
        let response = "Hola Juan, te paso el meeting link en un minuto."

        XCTAssertEqual(
            CorrectionOutputSanitizer.validated(response, fallingBackTo: original),
            response
        )
    }
}
