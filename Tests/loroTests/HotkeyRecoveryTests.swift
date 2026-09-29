import Testing
import LoroCore

struct HotkeyRecoveryTests {
    @Test func engineStartupTimeoutDoesNotReleaseAHeldShortcut() {
        #expect(!HotkeyRecovery.shouldRelease(isPressed: true, modifiersHeld: true, keyHeld: true))
    }
    @Test func releaseMissedWhileTapWasDisabledStopsCapture() {
        #expect(HotkeyRecovery.shouldRelease(isPressed: true, modifiersHeld: false, keyHeld: true))
        #expect(HotkeyRecovery.shouldRelease(isPressed: true, modifiersHeld: true, keyHeld: false))
    }
    @Test func recoveryCannotCreateAPressOrDuplicateAToggle() {
        #expect(!HotkeyRecovery.shouldRelease(isPressed: false, modifiersHeld: true, keyHeld: true))
        #expect(!HotkeyRecovery.shouldRelease(isPressed: false, modifiersHeld: false, keyHeld: false))
    }
}
