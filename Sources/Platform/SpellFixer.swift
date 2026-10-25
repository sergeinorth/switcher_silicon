import AppKit
import Engine

/// Conservative typo fixer.
///
/// macOS RU dictionary is noisy (flags real words, accepts junk), so we:
/// - EN: trust a unique Apple guess at edit distance 1
/// - RU / always: only accept fixes that land in our seed dictionary
///   (Apple guess ∩ seed, or phonetic / keyboard / transposition → seed)
public struct SpellFixer: @unchecked Sendable {
    private let validator = SystemWordValidator()

    public init() {}

    public func suggestion(for word: String) -> String? {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return nil }
        // Already real (full morph dict / system) — never "fix".
        if validator.isKnownWord(trimmed) || BundledDictionary.isSpellAcceptable(trimmed) {
            return nil
        }

        let script = ConversionEngine.dominantScript(trimmed)
        let language: String
        switch script {
        case .cyrillic: language = "ru"
        case .latin: language = "en"
        case .mixed, .other: return nil
        }

        // Phonetic / keyboard first: Apple RU guesses often prefer rare junk («пресет»).
        if let s = fromPhoneticSwaps(trimmed) {
            return applyCase(of: trimmed, to: s)
        }
        if let s = fromAdjacentTransposition(trimmed) {
            return applyCase(of: trimmed, to: s)
        }
        if let s = fromKeyboardSwaps(trimmed, script: script) {
            return applyCase(of: trimmed, to: s)
        }
        if let s = fromAppleGuesses(trimmed, language: language) {
            return applyCase(of: trimmed, to: s)
        }
        return nil
    }

    private func fromAppleGuesses(_ word: String, language: String) -> String? {
        let checker = NSSpellChecker.shared
        let nsWord = word as NSString
        let range = NSRange(location: 0, length: nsWord.length)

        let miss = checker.checkSpelling(
            of: word,
            startingAt: 0,
            language: language,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        guard miss.location != NSNotFound else { return nil }

        guard let guesses = checker.guesses(
            forWordRange: range,
            in: word,
            language: language,
            inSpellDocumentWithTag: 0
        ), !guesses.isEmpty else {
            return nil
        }

        let lower = word.lowercased()
        let close = guesses.filter { g in
            EditDistance.between(lower, g.lowercased(), limit: 1) == 1
        }
        // Only accept high-frequency / curated targets (not the full morph dump).
        let acceptHits = close.filter { BundledDictionary.isSpellAcceptable($0) }
        if acceptHits.count == 1, let only = acceptHits.first, only.lowercased() != lower {
            return only
        }
        // English: unique distance-1 Apple guess that is a known word.
        if language == "en" {
            let known = close.filter { validator.isKnownWord($0) }
            if known.count == 1, let only = known.first, only.lowercased() != lower {
                return only
            }
        }
        return nil
    }

    private func fromPhoneticSwaps(_ word: String) -> String? {
        let groups: [[Character]] = [
            Array("еиё"),
            Array("ао"),
            Array("шщ"),
            Array("ьъ"),
            Array("ыи"),
            Array("ei"),
            Array("ao"),
        ]
        return uniqueSeedSingleSwaps(word, replacingFrom: groups)
    }

    private func fromAdjacentTransposition(_ word: String) -> String? {
        var chars = Array(word.lowercased())
        guard chars.count >= 2 else { return nil }
        var hits = Set<String>()
        for i in 0..<(chars.count - 1) {
            chars.swapAt(i, i + 1)
            let candidate = String(chars)
            if BundledDictionary.isSpellAcceptable(candidate) {
                hits.insert(candidate)
            }
            chars.swapAt(i, i + 1)
        }
        guard hits.count == 1, let only = hits.first, only != word.lowercased() else {
            return nil
        }
        return only
    }

    private func fromKeyboardSwaps(_ word: String, script: ConversionEngine.Script) -> String? {
        let neighbors: [Character: [Character]]
        switch script {
        case .cyrillic: neighbors = Self.ruNeighbors
        case .latin: neighbors = Self.enNeighbors
        case .mixed, .other: return nil
        }
        let groups = neighbors.map { [$0.key] + $0.value }
        return uniqueSeedSingleSwaps(word, replacingFrom: groups)
    }

    private func uniqueSeedSingleSwaps(_ word: String, replacingFrom groups: [[Character]]) -> String? {
        let chars = Array(word.lowercased())
        var hits = Set<String>()
        for i in chars.indices {
            let ch = chars[i]
            let alts = groups.first(where: { $0.contains(ch) })?.filter { $0 != ch } ?? []
            for alt in alts {
                var copy = chars
                copy[i] = alt
                let candidate = String(copy)
                if BundledDictionary.isSpellAcceptable(candidate) {
                    hits.insert(candidate)
                }
            }
        }
        guard hits.count == 1, let only = hits.first, only != word.lowercased() else {
            return nil
        }
        return only
    }

    private func applyCase(of original: String, to suggestion: String) -> String {
        if let first = original.first, first.isUppercase {
            return suggestion.prefix(1).uppercased() + suggestion.dropFirst()
        }
        return suggestion
    }

    private static let ruNeighbors: [Character: [Character]] = [
        "й": ["ц", "ф", "ы"],
        "ц": ["й", "у", "ы", "в", "ф"],
        "у": ["ц", "к", "в", "а", "ы"],
        "к": ["у", "е", "а", "п", "в"],
        "е": ["к", "н", "п", "р", "а"],
        "н": ["е", "г", "р", "о", "п"],
        "г": ["н", "ш", "о", "л", "р"],
        "ш": ["г", "щ", "л", "д", "о"],
        "щ": ["ш", "з", "д", "ж", "л"],
        "з": ["щ", "х", "ж", "э", "д"],
        "х": ["з", "ъ", "э"],
        "ъ": ["х", "э"],
        "ф": ["й", "ы", "я", "ц"],
        "ы": ["ф", "в", "я", "ч", "ц", "у"],
        "в": ["ы", "а", "ч", "с", "у", "к"],
        "а": ["в", "п", "с", "м", "к", "е"],
        "п": ["а", "р", "м", "и", "е", "н"],
        "р": ["п", "о", "и", "т", "н", "г"],
        "о": ["р", "л", "т", "ь", "г", "ш"],
        "л": ["о", "д", "ь", "б", "ш", "щ"],
        "д": ["л", "ж", "б", "ю", "щ", "з"],
        "ж": ["д", "э", "ю", "з", "х"],
        "э": ["ж", "х", "ъ"],
        "я": ["ф", "ы", "ч"],
        "ч": ["я", "с", "ы", "в"],
        "с": ["ч", "м", "в", "а"],
        "м": ["с", "и", "а", "п"],
        "и": ["м", "т", "п", "р"],
        "т": ["и", "ь", "р", "о"],
        "ь": ["т", "б", "о", "л"],
        "б": ["ь", "ю", "л", "д"],
        "ю": ["б", "д", "ж"],
    ]

    private static let enNeighbors: [Character: [Character]] = [
        "q": ["w", "a"],
        "w": ["q", "e", "a", "s"],
        "e": ["w", "r", "s", "d"],
        "r": ["e", "t", "d", "f"],
        "t": ["r", "y", "f", "g"],
        "y": ["t", "u", "g", "h"],
        "u": ["y", "i", "h", "j"],
        "i": ["u", "o", "j", "k"],
        "o": ["i", "p", "k", "l"],
        "p": ["o", "l"],
        "a": ["q", "w", "s", "z"],
        "s": ["a", "w", "e", "d", "z", "x"],
        "d": ["s", "e", "r", "f", "x", "c"],
        "f": ["d", "r", "t", "g", "c", "v"],
        "g": ["f", "t", "y", "h", "v", "b"],
        "h": ["g", "y", "u", "j", "b", "n"],
        "j": ["h", "u", "i", "k", "n", "m"],
        "k": ["j", "i", "o", "l", "m"],
        "l": ["k", "o", "p"],
        "z": ["a", "s", "x"],
        "x": ["z", "s", "d", "c"],
        "c": ["x", "d", "f", "v"],
        "v": ["c", "f", "g", "b"],
        "b": ["v", "g", "h", "n"],
        "n": ["b", "h", "j", "m"],
        "m": ["n", "j", "k"],
    ]
}
