import AppKit
import Engine

/// Conservative typo fixer: only when spellchecker has a single close guess.
public struct SpellFixer: Sendable {
    public init() {}

    public func suggestion(for word: String) -> String? {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return nil }

        let script = ConversionEngine.dominantScript(trimmed)
        let language: String
        switch script {
        case .cyrillic: language = "ru"
        case .latin: language = "en"
        case .mixed, .other: return nil
        }

        let checker = NSSpellChecker.shared
        let full = trimmed as NSString
        let range = NSRange(location: 0, length: full.length)
        let miss = checker.checkSpelling(
            of: trimmed,
            startingAt: 0,
            language: language,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        // No misspelling reported — leave as is.
        guard miss.location != NSNotFound else { return nil }

        guard let guesses = checker.guesses(
            forWordRange: range,
            in: trimmed,
            language: language,
            inSpellDocumentWithTag: 0
        ), !guesses.isEmpty else {
            return nil
        }

        // Keep only close edits; require a unique best distance of 1 (or single guess at 2).
        let lower = trimmed.lowercased()
        let scored = guesses.map { g in (g, EditDistance.between(lower, g.lowercased(), limit: 2)) }
            .filter { $0.1 <= 2 }
            .sorted { $0.1 < $1.1 }

        guard let best = scored.first else { return nil }
        let bestDist = best.1
        let bestGroup = scored.filter { $0.1 == bestDist }
        // Ambiguous: several equally good fixes — do nothing.
        guard bestGroup.count == 1 else { return nil }
        // Distance 2 only if that unique guess is the sole candidate from the checker.
        if bestDist == 2 && guesses.count > 1 { return nil }

        let suggestion = bestGroup[0].0
        if suggestion.lowercased() == lower { return nil }

        // Preserve simple capitalization: first letter upper → keep.
        if let first = trimmed.first, first.isUppercase {
            return suggestion.prefix(1).uppercased() + suggestion.dropFirst()
        }
        return suggestion
    }
}
