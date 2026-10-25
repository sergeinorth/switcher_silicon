import AppKit
import Engine

/// Conservative typo fixer: distance 1 only, unique guess, suggestion must be a known word.
public struct SpellFixer: @unchecked Sendable {
    private let validator = SystemWordValidator()

    public init() {}

    public func suggestion(for word: String) -> String? {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return nil }

        // Already a known word — never "fix".
        if validator.isKnownWord(trimmed) { return nil }

        let script = ConversionEngine.dominantScript(trimmed)
        let language: String
        switch script {
        case .cyrillic: language = "ru"
        case .latin: language = "en"
        case .mixed, .other: return nil
        }

        let checker = NSSpellChecker.shared
        let nsWord = trimmed as NSString
        let range = NSRange(location: 0, length: nsWord.length)

        let miss = checker.checkSpelling(
            of: trimmed,
            startingAt: 0,
            language: language,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        guard miss.location != NSNotFound else { return nil }

        guard let guesses = checker.guesses(
            forWordRange: range,
            in: trimmed,
            language: language,
            inSpellDocumentWithTag: 0
        ), !guesses.isEmpty else {
            return nil
        }

        let lower = trimmed.lowercased()
        // Only edit distance 1, and suggestion must be a real dictionary word.
        let close = guesses.filter { g in
            let d = EditDistance.between(lower, g.lowercased(), limit: 1)
            return d == 1 && validator.isKnownWord(g)
        }

        // Unique close known guess only.
        guard close.count == 1, let suggestion = close.first else { return nil }
        if suggestion.lowercased() == lower { return nil }

        if let first = trimmed.first, first.isUppercase {
            return suggestion.prefix(1).uppercased() + suggestion.dropFirst()
        }
        return suggestion
    }
}
