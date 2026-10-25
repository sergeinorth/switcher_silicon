import Foundation

public struct ConversionSnapshot: Equatable, Sendable {
    public var original: String
    public var converted: String
    public var switchedToRussian: Bool
    public var createdAt: Date

    public init(original: String, converted: String, switchedToRussian: Bool, createdAt: Date = Date()) {
        self.original = original
        self.converted = converted
        self.switchedToRussian = switchedToRussian
        self.createdAt = createdAt
    }
}

public struct UndoState: Equatable, Sendable {
    public var last: ConversionSnapshot?
    public var learnedNever: Set<String>

    public init(last: ConversionSnapshot? = nil, learnedNever: Set<String> = []) {
        self.last = last
        self.learnedNever = learnedNever
    }

    public mutating func remember(_ snapshot: ConversionSnapshot) {
        last = snapshot
    }

    public mutating func clearLast() {
        last = nil
    }

    public mutating func learnNever(_ word: String) {
        learnedNever.insert(word.lowercased())
    }
}
