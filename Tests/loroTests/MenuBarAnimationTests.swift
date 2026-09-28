import Testing
@testable import LoroCore

final class MenuBarAnimationTests {
    @Test func testQuietAudioUsesCalmWaveFrame() {
        #expect(MenuBarAnimation.recordingFrame(for: 0) == 0)
        #expect(MenuBarAnimation.recordingFrame(for: 0.005) == 0)
    }

    @Test func testSpeechExpandsTheWaveFrame() {
        #expect(MenuBarAnimation.recordingFrame(for: 0.006) == 1)
        #expect(MenuBarAnimation.recordingFrame(for: 0.019) == 1)
        #expect(MenuBarAnimation.recordingFrame(for: 0.02) == 2)
    }

    @Test func testInvalidAudioLevelFallsBackToCalmFrame() {
        #expect(MenuBarAnimation.recordingFrame(for: .nan) == 0)
    }

    @Test func testDotsCycleAcrossThreeFrames() {
        #expect(MenuBarAnimation.nextDotsFrame(after: 0) == 1)
        #expect(MenuBarAnimation.nextDotsFrame(after: 1) == 2)
        #expect(MenuBarAnimation.nextDotsFrame(after: 2) == 0)
        #expect(MenuBarAnimation.nextDotsFrame(after: -1) == 0)
    }
}
