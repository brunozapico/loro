import ApplicationServices
import CoreGraphics
import Foundation

/// Posts a string of text at the current cursor location by synthesizing
/// keyboard events with `CGEventKeyboardSetUnicodeString`. Works in nearly
/// every text field on macOS; some Electron apps and secure password fields
/// can drop characters (platform constraint).
enum TextInjector {
    /// Inject the given text at the current cursor location.
    /// Splits long strings into chunks because the underlying API has a
    /// per-event character limit (~20 chars).
    @discardableResult
    static func inject(_ text: String) -> Bool {
        guard !text.isEmpty, AXIsProcessTrusted() else { return false }

        let utf16 = Array(text.utf16)
        let chunkSize = 20
        var index = 0

        while index < utf16.count {
            let end = min(index + chunkSize, utf16.count)
            var chunk = Array(utf16[index..<end])
            guard postChunk(&chunk) else { return false }
            index = end
        }

        return true
    }

    private static func postChunk(_ chunk: inout [UniChar]) -> Bool {
        let length = chunk.count
        guard length > 0 else { return false }

        let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
        guard let down, let up else { return false }

        down.keyboardSetUnicodeString(stringLength: length, unicodeString: &chunk)
        down.post(tap: .cgSessionEventTap)
        up.keyboardSetUnicodeString(stringLength: length, unicodeString: &chunk)
        up.post(tap: .cgSessionEventTap)
        return true
    }
}
