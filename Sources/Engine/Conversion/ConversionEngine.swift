import Foundation

/// Bidirectional QWERTY US <-> Russian (ЙЦУКЕН) character mapping.
public enum ConversionEngine: Sendable {
    private static let usToRu: [Character: Character] = {
        let pairs: [(Character, Character)] = [
            ("q", "й"), ("w", "ц"), ("e", "у"), ("r", "к"), ("t", "е"),
            ("y", "н"), ("u", "г"), ("i", "ш"), ("o", "щ"), ("p", "з"),
            ("[", "х"), ("]", "ъ"), ("a", "ф"), ("s", "ы"), ("d", "в"),
            ("f", "а"), ("g", "п"), ("h", "р"), ("j", "о"), ("k", "л"),
            ("l", "д"), (";", "ж"), ("'", "э"), ("z", "я"), ("x", "ч"),
            ("c", "с"), ("v", "м"), ("b", "и"), ("n", "т"), ("m", "ь"),
            (",", "б"), (".", "ю"), ("`", "ё"),
            ("Q", "Й"), ("W", "Ц"), ("E", "У"), ("R", "К"), ("T", "Е"),
            ("Y", "Н"), ("U", "Г"), ("I", "Ш"), ("O", "Щ"), ("P", "З"),
            ("{", "Х"), ("}", "Ъ"), ("A", "Ф"), ("S", "Ы"), ("D", "В"),
            ("F", "А"), ("G", "П"), ("H", "Р"), ("J", "О"), ("K", "Л"),
            ("L", "Д"), (":", "Ж"), ("\"", "Э"), ("Z", "Я"), ("X", "Ч"),
            ("C", "С"), ("V", "М"), ("B", "И"), ("N", "Т"), ("M", "Ь"),
            ("<", "Б"), (">", "Ю"), ("~", "Ё"),
            ("/", "."), ("?", ","), ("@", "\""), ("#", "№"), ("$", ";"),
            ("^", ":"), ("&", "?"),
        ]
        return Dictionary(uniqueKeysWithValues: pairs)
    }()

    private static let ruToUs: [Character: Character] = {
        Dictionary(uniqueKeysWithValues: usToRu.map { ($0.value, $0.key) })
    }()

    // Cached once — LayoutChecker used to rebuild these Sets on every Space.
    public static let usToRuKeys: Set<Character> = Set(usToRu.keys)
    public static let ruToUsKeys: Set<Character> = Set(ruToUs.keys)

    public enum Direction: Sendable {
        case usToRussian
        case russianToUs
        case auto
    }

    public static func convert(_ text: String, direction: Direction = .auto) -> String {
        switch direction {
        case .usToRussian:
            return map(text, using: usToRu)
        case .russianToUs:
            return map(text, using: ruToUs)
        case .auto:
            let script = dominantScript(text)
            switch script {
            case .latin:
                return map(text, using: usToRu)
            case .cyrillic:
                return map(text, using: ruToUs)
            case .mixed, .other:
                // Prefer converting as if typed in Latin (common "wrong layout" case on RU machines).
                if text.contains(where: { usToRu[$0] != nil }) {
                    return map(text, using: usToRu)
                }
                return map(text, using: ruToUs)
            }
        }
    }

    /// Flip each mappable character EN↔RU (for selections that may mix scripts/spaces).
    public static func flipLayout(_ text: String) -> String {
        String(text.map { ch in
            if let ru = usToRu[ch] { return ru }
            if let us = ruToUs[ch] { return us }
            return ch
        })
    }

    public enum Script: Sendable {
        case latin, cyrillic, mixed, other
    }

    public static func dominantScript(_ text: String) -> Script {
        var latin = 0
        var cyrillic = 0
        for ch in text where ch.isLetter {
            if ch.isASCII {
                latin += 1
            } else if ch.unicodeScalars.allSatisfy({ (0x0400...0x04FF).contains($0.value) }) {
                cyrillic += 1
            }
        }
        if latin == 0 && cyrillic == 0 { return .other }
        if latin > 0 && cyrillic > 0 { return .mixed }
        return latin > cyrillic ? .latin : .cyrillic
    }

    private static func map(_ text: String, using table: [Character: Character]) -> String {
        String(text.map { table[$0] ?? $0 })
    }
}
