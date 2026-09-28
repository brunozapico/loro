import Testing
@testable import LoroCore

final class TranscriptionDeliveryPolicyTests {
    @Test func testAutomaticCopyCopiesAfterSuccessfulInjection() {
        #expect(
            TranscriptionDeliveryPolicy.shouldCopy(
                automaticCopyEnabled: true,
                injectionSucceeded: true
            )
        )
    }

    @Test func testAutomaticCopyCopiesAfterFailedInjection() {
        #expect(
            TranscriptionDeliveryPolicy.shouldCopy(
                automaticCopyEnabled: true,
                injectionSucceeded: false
            )
        )
    }

    @Test func testDisabledAutomaticCopyPreservesClipboardAfterFailure() {
        #expect(
            TranscriptionDeliveryPolicy.shouldCopy(
                automaticCopyEnabled: false,
                injectionSucceeded: false
            )
        )
    }

    @Test func testDisabledAutomaticCopyLeavesClipboardAloneAfterSuccess() {
        #expect(!TranscriptionDeliveryPolicy.shouldCopy(
                automaticCopyEnabled: false,
                injectionSucceeded: true
            ))
    }
}
