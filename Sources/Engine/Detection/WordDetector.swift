import Foundation

public enum WordDetector: Sendable {
    /// Only real word boundaries. US `,` `.` `;` `'` `[` `]` are RU letters
    /// (б ю ж э х ъ) when typed in the wrong layout — never treat them as separators.
    public static let separators: Set<Character> = [
        " ", "\t", "\n", "\r",
    ]

    public static func isSeparator(_ character: Character) -> Bool {
        separators.contains(character)
    }

    public static func isSeparatorKeyCode(_ keyCode: UInt16) -> Bool {
        // Space, Tab, Return, keypad Enter
        keyCode == 49 || keyCode == 48 || keyCode == 36 || keyCode == 76
    }

    public static func isBackspace(_ keyCode: UInt16) -> Bool {
        keyCode == 51
    }

    public static func isEscape(_ keyCode: UInt16) -> Bool {
        keyCode == 53
    }

    /// Arrows / Home / End / Page Up/Down — cursor left the typed word.
    public static func isNavigation(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 123, 124, 125, 126, 115, 119, 116, 121:
            return true
        default:
            return false
        }
    }

    public static func separatorString(forKeyCode keyCode: UInt16) -> String {
        switch keyCode {
        case 49: return " "
        case 48: return "\t"
        case 36, 76: return "\n"
        default: return " "
        }
    }
}
