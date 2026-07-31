import XCTest
@testable import LoroCore

final class SilenceDetectorTests: XCTestCase {
    func testStopsAfterDefaultFiveSecondsWithoutSpeech() {
        var detector = SilenceDetector(timeout: 5)
        detector.start(at: 10)

        XCTAssertFalse(detector.shouldStop(at: 14.99))
        XCTAssertTrue(detector.shouldStop(at: 15))
    }

    func testSpeechResetsTheCountdown() {
        var detector = SilenceDetector(timeout: 5)
        detector.start(at: 0)
        detector.observe(level: 0.03, at: 4)

        XCTAssertFalse(detector.shouldStop(at: 8.99))
        XCTAssertTrue(detector.shouldStop(at: 9))
    }

    func testQuietBuffersDoNotResetTheCountdown() {
        var detector = SilenceDetector(timeout: 5, speechThreshold: 0.012)
        detector.start(at: 0)
        detector.observe(level: 0.011, at: 4)

        XCTAssertTrue(detector.shouldStop(at: 5))
    }

    func testNonFiniteLevelsAreIgnored() {
        var detector = SilenceDetector(timeout: 5)
        detector.start(at: 0)
        detector.observe(level: .nan, at: 4)

        XCTAssertTrue(detector.shouldStop(at: 5))
    }

    func testResetDisablesTimeoutUntilTheNextRecording() {
        var detector = SilenceDetector(timeout: 5)
        detector.start(at: 0)
        detector.reset()

        XCTAssertFalse(detector.shouldStop(at: 100))
    }
}
