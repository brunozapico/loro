import XCTest
@testable import LoroCore

final class TranscriptionDeliveryPolicyTests: XCTestCase {
    func testAutomaticCopyCopiesAfterSuccessfulInjection() {
        XCTAssertTrue(
            TranscriptionDeliveryPolicy.shouldCopy(
                automaticCopyEnabled: true,
                injectionSucceeded: true
            )
        )
    }

    func testAutomaticCopyCopiesAfterFailedInjection() {
        XCTAssertTrue(
            TranscriptionDeliveryPolicy.shouldCopy(
                automaticCopyEnabled: true,
                injectionSucceeded: false
            )
        )
    }

    func testDisabledAutomaticCopyPreservesClipboardAfterFailure() {
        XCTAssertTrue(
            TranscriptionDeliveryPolicy.shouldCopy(
                automaticCopyEnabled: false,
                injectionSucceeded: false
            )
        )
    }

    func testDisabledAutomaticCopyLeavesClipboardAloneAfterSuccess() {
        XCTAssertFalse(
            TranscriptionDeliveryPolicy.shouldCopy(
                automaticCopyEnabled: false,
                injectionSucceeded: true
            )
        )
    }
}
