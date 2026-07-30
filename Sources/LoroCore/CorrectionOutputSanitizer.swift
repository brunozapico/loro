import Foundation

/// Removes model-protocol formatting before corrected text reaches the cursor.
///
/// Foundation Models usually follows the plain-text response instruction, but
/// it can occasionally emit XML-like wrappers or Markdown fences. Those tokens
/// are implementation details and must never become user-visible dictation.
public enum CorrectionOutputSanitizer {
    private static let controlTagPattern =
        #"(?i)<\s*/?\s*(?:corrected[\s_-]*fragment|current[\s_-]*fragment|fragment)\b[^>]*>"#
    private static let escapedControlTagPattern =
        #"(?i)&lt;\s*/?\s*(?:corrected[\s_-]*fragment|current[\s_-]*fragment|fragment)\b[^&]*?&gt;"#
    private static let controlLabelPattern =
        #"(?i)^\s*(?:corrected[\s_-]*fragment|current[\s_-]*fragment|output|response|answer)\s*:\s*"#
    private static let residualMarkerPattern =
        #"(?i)corrected[\s_-]*fragment|current[\s_-]*fragment"#

    public static func validated(
        _ candidate: String?,
        fallingBackTo original: String
    ) -> String {
        let fallback = sanitized(original)
            ?? original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let candidate,
              let cleaned = sanitized(candidate),
              !cleaned.isEmpty,
              cleaned.count <= max(original.count * 2 + 64, 160)
        else {
            return fallback
        }
        return cleaned
    }

    private static func sanitized(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        text = removingMarkdownFence(from: text)
        text = replacingMatches(in: text, pattern: controlTagPattern, with: "")
        text = replacingMatches(in: text, pattern: escapedControlTagPattern, with: "")
        text = replacingMatches(in: text, pattern: controlLabelPattern, with: "")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty,
              !containsMatch(in: text, pattern: residualMarkerPattern),
              !text.hasPrefix("```")
        else {
            return nil
        }
        return text
    }

    private static func removingMarkdownFence(from input: String) -> String {
        guard input.hasPrefix("```"),
              let firstLineBreak = input.firstIndex(of: "\n")
        else {
            return input
        }

        var body = String(input[input.index(after: firstLineBreak)...])
        if body.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("```"),
           let closingFence = body.range(
               of: #"(?s)\s*```\s*$"#,
               options: .regularExpression
           )
        {
            body.removeSubrange(closingFence)
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replacingMatches(
        in input: String,
        pattern: String,
        with replacement: String
    ) -> String {
        input.replacingOccurrences(
            of: pattern,
            with: replacement,
            options: .regularExpression
        )
    }

    private static func containsMatch(in input: String, pattern: String) -> Bool {
        input.range(of: pattern, options: .regularExpression) != nil
    }
}
