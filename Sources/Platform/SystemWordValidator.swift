import AppKit
import Engine

/// Uses macOS spell checker (RU + EN) plus the seed dictionary.
public struct SystemWordValidator: WordValidator, @unchecked Sendable {
    private let seed = SeedWordValidator()
    private let languages = ["ru", "en"]

    public init() {}

    public func isKnownWord(_ word: String) -> Bool {
        let lower = word.lowercased()
        if seed.isKnownWord(lower) { return true }
        if lower.count < 2 { return false }

        let checker = NSSpellChecker.shared
        for language in languages {
            // NSNotFound => no misspelling from offset 0 => word is accepted.
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
