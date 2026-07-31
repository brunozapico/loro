import AppKit

enum ClipboardWriter {
    /// Replaces the current pasteboard contents with the final transcript.
    /// Loro keeps no separate clipboard or transcript history.
    @discardableResult
    static func copy(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}
