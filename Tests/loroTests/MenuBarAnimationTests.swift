import XCTest
@testable import LoroCore

final class MenuBarAnimationTests: XCTestCase {
    func testQuietAudioUsesCalmWaveFrame() {
        XCTAssertEqual(MenuBarAnimation.recordingFrame(for: 0), 0)
        XCTAssertEqual(MenuBarAnimation.recordingFrame(for: 0.005), 0)
    }

    func testSpeechExpandsTheWaveFrame() {
        XCTAssertEqual(MenuBarAnimation.recordingFrame(for: 0.006), 1)
        XCTAssertEqual(MenuBarAnimation.recordingFrame(for: 0.019), 1)
        XCTAssertEqual(MenuBarAnimation.recordingFrame(for: 0.02), 2)
    }

    func testInvalidAudioLevelFallsBackToCalmFrame() {
        XCTAssertEqual(MenuBarAnimation.recordingFrame(for: .nan), 0)
    }

    func testDotsCycleAcrossThreeFrames() {
        XCTAssertEqual(MenuBarAnimation.nextDotsFrame(after: 0), 1)
        XCTAssertEqual(MenuBarAnimation.nextDotsFrame(after: 1), 2)
        XCTAssertEqual(MenuBarAnimation.nextDotsFrame(after: 2), 0)
        XCTAssertEqual(MenuBarAnimation.nextDotsFrame(after: -1), 0)
    }
}
