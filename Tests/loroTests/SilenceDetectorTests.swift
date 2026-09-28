import Testing
@testable import LoroCore

final class SilenceDetectorTests {
    @Test func testStopsAfterDefaultFiveSecondsWithoutSpeech() {
        var detector = SilenceDetector(timeout: 5)
        detector.start(at: 10)

        #expect(!detector.shouldStop(at: 14.99))
        #expect(detector.shouldStop(at: 15))
    }

    @Test func testSpeechResetsTheCountdown() {
        var detector = SilenceDetector(timeout: 5)
        detector.start(at: 0)
        detector.observe(level: 0.03, at: 4)

        #expect(!detector.shouldStop(at: 8.99))
        #expect(detector.shouldStop(at: 9))
    }

    @Test func testQuietBuffersDoNotResetTheCountdown() {
        var detector = SilenceDetector(timeout: 5, speechThreshold: 0.012)
        detector.start(at: 0)
        detector.observe(level: 0.011, at: 4)

        #expect(detector.shouldStop(at: 5))
    }

    @Test func testNonFiniteLevelsAreIgnored() {
        var detector = SilenceDetector(timeout: 5)
        detector.start(at: 0)
        detector.observe(level: .nan, at: 4)

        #expect(detector.shouldStop(at: 5))
    }

    @Test func testResetDisablesTimeoutUntilTheNextRecording() {
        var detector = SilenceDetector(timeout: 5)
        detector.start(at: 0)
        detector.reset()

        #expect(!detector.shouldStop(at: 100))
    }
}
