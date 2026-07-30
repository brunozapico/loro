import Foundation

/// A user-defined phrase substitution applied only to the in-memory
/// transcription immediately before text injection.
struct ReplacementRule: Codable, Equatable, Identifiable {
    var id: UUID
    var spokenPhrase: String
    var replacement: String

    init(id: UUID = UUID(), spokenPhrase: String = "", replacement: String = "") {
        self.id = id
        self.spokenPhrase = spokenPhrase
        self.replacement = replacement
    }
}

enum TextReplacementEngine {
    static func apply(_ rules: [ReplacementRule], to text: String) -> String {
        let activeRules = rules.enumerated()
            .compactMap { index, rule -> (spokenPhrase: String, replacement: String, sourceIndex: Int)? in
                let spokenPhrase = rule.spokenPhrase
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let replacement = rule.replacement
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !spokenPhrase.isEmpty, !replacement.isEmpty else { return nil }
                return (spokenPhrase, replacement, index)
            }
            .sorted {
                if $0.spokenPhrase.count == $1.spokenPhrase.count {
                    return $0.sourceIndex < $1.sourceIndex
                }
                return $0.spokenPhrase.count > $1.spokenPhrase.count
            }

        guard !activeRules.isEmpty else { return text }

        // Whisper commonly adds sentence-ending punctuation. If the entire
        // utterance is a trigger phrase, return exactly the configured value
        // so an email address or code is not followed by an unwanted period.
        let utterance = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
        if let exactRule = activeRules.first(where: {
            utterance.compare(
                $0.spokenPhrase,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame
        }) {
            return exactRule.replacement
        }

        // Stage matches behind unique placeholders so one rule's replacement
        // cannot accidentally trigger a second rule.
        var stagedText = text
        var stagedReplacements: [(placeholder: String, replacement: String)] = []
        for (index, rule) in activeRules.enumerated() {
            // Plane 15 is a Unicode private-use area, so ordinary dictated
            // text and user triggers cannot collide with these placeholders.
            let scalarValue = 0xF0000 + index
            guard let scalar = UnicodeScalar(scalarValue) else { continue }
            let placeholder = String(Character(scalar))
            let replaced = stagedText.replacingOccurrences(
                of: rule.spokenPhrase,
                with: placeholder,
                options: [.caseInsensitive, .diacriticInsensitive]
            )
            if replaced != stagedText {
                stagedText = replaced
                stagedReplacements.append((placeholder, rule.replacement))
            }
        }

        return stagedReplacements.reduce(stagedText) { result, staged in
            result.replacingOccurrences(
                of: staged.placeholder,
                with: staged.replacement
            )
        }
    }
}
