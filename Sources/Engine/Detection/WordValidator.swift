import Foundation

public protocol WordValidator: Sendable {
    func isKnownWord(_ word: String) -> Bool
}

/// Built-in seed lists plus bundled open dictionaries.
public struct SeedWordValidator: WordValidator {
    private let extra: Set<String>

    public init(extra: Set<String> = []) {
        self.extra = extra
    }

    public func isKnownWord(_ word: String) -> Bool {
        let lower = word.lowercased()
        if extra.contains(lower) { return true }
        if SeedDictionary.russian.contains(lower) || SeedDictionary.english.contains(lower) {
            return true
        }
        // Large bundled lists (lazy-loaded once).
        switch ConversionEngine.dominantScript(lower) {
        case .cyrillic:
            return BundledDictionary.sharedRussian.contains(lower)
        case .latin:
            return BundledDictionary.sharedEnglish.contains(lower)
        case .mixed, .other:
            return BundledDictionary.sharedRussian.contains(lower)
                || BundledDictionary.sharedEnglish.contains(lower)
        }
    }
}

public struct AnyWordValidator: WordValidator {
    private let impl: @Sendable (String) -> Bool

    public init(_ impl: @escaping @Sendable (String) -> Bool) {
        self.impl = impl
    }

    public func isKnownWord(_ word: String) -> Bool {
        impl(word)
    }
}
