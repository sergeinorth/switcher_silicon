import AppKit
import Engine

/// Uses macOS spell checker (RU + EN) plus the seed dictionary.
/// Important: only ask a language checker about words in that script.
/// English NSSpellChecker returns NSNotFound for pure Cyrillic (nothing to flag),
/// which wrongly looked like "known word" and blocked RU→EN conversion.
public struct SystemWordValidator: WordValidator, @unchecked Sendable {
    private let seed = SeedWordValidator()

    public init() {}

    public func isKnownWord(_ word: String) -> Bool {
        let lower = word.lowercased()
        if seed.isKnownWord(lower) { return true }
        if lower.count < 2 { return false }

        let languages: [String]
        switch ConversionEngine.dominantScript(lower) {
        case .latin:
            languages = ["en"]
        case .cyrillic:
            languages = ["ru"]
        case .mixed, .other:
            languages = ["en", "ru"]
        }

        let checker = NSSpellChecker.shared
        for language in languages {
            let range = checker.checkSpelling(
                of: lower,
                startingAt: 0,
                language: language,
                wrap: false,
                inSpellDocumentWithTag: 0,
                wordCount: nil
            )
            if range.location == NSNotFound {
                return true
            }
        }
        return false
    }
}
