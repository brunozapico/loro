/// Recover a suspended event tap without interpreting its timeout as key-up.
public enum HotkeyRecovery {
    public static func shouldRelease(isPressed: Bool, modifiersHeld: Bool, keyHeld: Bool) -> Bool {
        isPressed && !(modifiersHeld && keyHeld)
    }
}
