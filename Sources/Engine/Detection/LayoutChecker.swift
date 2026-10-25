import Foundation

public enum LayoutCheckResult: Equatable, Sendable {
    case unknown
    case incorrect
    case exception
}

/// Convert when the flipped form is a known word and the typed form is not.
public struct LayoutChecker: Sendable {
    private let validator: any WordValidator
    private let alwaysConvert: Set<String>
    private let neverConvert: Set<String>
    private let userRules: [UserRule]

    public init(
        validator: any WordValidator = SeedWordValidator(),
        alwaysConvert: Set<String> = [],
        neverConvert: Set<String> = [],
        userRules: [UserRule] = []
    ) {
        self.validator = validator
        self.alwaysConvert = alwaysConvert
        self.neverConvert = neverConvert
        self.userRules = userRules
    }

    public func check(_ typed: String) -> LayoutCheckResult {
        let word = typed
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { ch in
                ch.isLetter || ch == "'" || ch == "-" || ch == "’"
                    || ConversionEngine.usToRuKeys.contains(ch)
                    || ConversionEngine.ruToUsKeys.contains(ch)
            }
        guard word.count >= 2 else { return .unknown }

        let lower = word.lowercased()

        if neverConvert.contains(lower) { return .exception }
        if alwaysConvert.contains(lower) { return .incorrect }

        for rule in userRules where rule.isActive {
            if matches(rule, word: word) {
                return rule.shouldSwitch ? .incorrect : .exception
            }
        }

        let converted = ConversionEngine.convert(word, direction: .auto)
        let convertedLower = converted.lowercased()
        if convertedLower == lower { return .unknown }

        let typedKnown = validator.isKnownWord(lower)
        let convertedKnown = validator.isKnownWord(convertedLower)

        if typedKnown { return .unknown }
        if convertedKnown { return .incorrect }

        return .unknown
    }

    private func matches(_ rule: UserRule, word: String) -> Bool {
        if rule.isRegex {
            return (try? NSRegularExpression(pattern: rule.pattern, options: [.caseInsensitive]))
                .map { regex in
                    let range = NSRange(word.startIndex..., in: word)
                    return regex.firstMatch(in: word, options: [], range: range) != nil
                } ?? false
        }
        return word.caseInsensitiveCompare(rule.pattern) == .orderedSame
    }
}
