public enum MenuBarAnimation {
    /// Keeps quiet audio visually calm while allowing normal and loud speech
    /// to expand the sound waves beside the parrot's beak.
    public static func recordingFrame(for level: Float) -> Int {
        guard level.isFinite else { return 0 }
        if level < 0.006 { return 0 }
        if level < 0.02 { return 1 }
        return 2
    }

    public static func nextDotsFrame(after frame: Int) -> Int {
        guard (0..<3).contains(frame) else { return 0 }
        return (frame + 1) % 3
    }
}
