import Foundation

/// Physical keycode → US QWERTY glyph (letters / digit row punctuation used in RU maps).
public enum KeyCodeMap: Sendable {
    public static func usCharacter(keyCode: UInt16, shift: Bool) -> String? {
        let table: [UInt16: (String, String)] = [
            0: ("a", "A"), 1: ("s", "S"), 2: ("d", "D"), 3: ("f", "F"),
            4: ("h", "H"), 5: ("g", "G"), 6: ("z", "Z"), 7: ("x", "X"),
            8: ("c", "C"), 9: ("v", "V"), 11: ("b", "B"), 12: ("q", "Q"),
            13: ("w", "W"), 14: ("e", "E"), 15: ("r", "R"), 16: ("y", "Y"),
            17: ("t", "T"), 18: ("1", "!"), 19: ("2", "@"), 20: ("3", "#"),
            21: ("4", "$"), 22: ("6", "^"), 23: ("5", "%"), 24: ("=", "+"),
            25: ("9", "("), 26: ("7", "&"), 27: ("-", "_"), 28: ("8", "*"),
            29: ("0", ")"), 30: ("]", "}"), 31: ("o", "O"), 32: ("u", "U"),
            33: ("[", "{"), 34: ("i", "I"), 35: ("p", "P"), 37: ("l", "L"),
            38: ("j", "J"), 39: ("'", "\""), 40: ("k", "K"), 41: (";", ":"),
            42: ("\\", "|"), 43: (",", "<"), 44: ("/", "?"), 45: ("n", "N"),
            46: ("m", "M"), 47: (".", ">"), 50: ("`", "~"),
        ]
        guard let pair = table[keyCode] else { return nil }
        return shift ? pair.1 : pair.0
    }
}
