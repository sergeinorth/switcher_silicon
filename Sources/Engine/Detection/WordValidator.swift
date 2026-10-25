import Foundation

public protocol WordValidator: Sendable {
    func isKnownWord(_ word: String) -> Bool
}

/// Built-in seed lists only.
public struct SeedWordValidator: WordValidator {
    private let words: Set<String>

    public init(extra: Set<String> = []) {
        self.words = SeedDictionary.russian
            .union(SeedDictionary.english)
            .union(extra)
    }

    public func isKnownWord(_ word: String) -> Bool {
        words.contains(word.lowercased())
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
