import Foundation

public enum WordDetector: Sendable {
    /// Characters that end the current word and may trigger auto-conversion.
    public static let separators: Set<Character> = [
        " ", "\t", "\n", "\r",
        ".", ",", "!", "?", ";", ":",
        "(", ")", "[", "]", "{", "}",
        "\"", "'", "«", "»",
        "/", "\\", "|", "-", "—", "–",
    ]

    public static func isSeparator(_ character: Character) -> Bool {
        separators.contains(character)
    }

    public static func isSeparatorKeyCode(_ keyCode: UInt16) -> Bool {
        // Space, Tab, Return
        keyCode == 49 || keyCode == 48 || keyCode == 36 || keyCode == 76
    }

    public static func isBackspace(_ keyCode: UInt16) -> Bool {
        keyCode == 51
    }

    public static func isEscape(_ keyCode: UInt16) -> Bool {
        keyCode == 53
    }
}
