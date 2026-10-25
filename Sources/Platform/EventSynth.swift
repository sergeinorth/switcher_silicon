import AppKit
import Carbon

public enum EventSynth {
    private static let sourceID: Int64 = 0x53575349 // 'SWSI'

    /// Set while we emit backspaces / unicode so the tap ignores side effects.
    nonisolated(unsafe) public static var isSynthesizing = false

    public static func markAsOurs(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: sourceID)
    }

    public static func isOurs(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == sourceID
    }

    public static func deleteBackward(times: Int) {
        guard times > 0 else { return }
        for _ in 0..<times {
            postKey(keyCode: 51, keyDown: true)
            postKey(keyCode: 51, keyDown: false)
            usleep(2_000)
        }
    }

    /// Type one Unicode scalar/cluster at a time (keyDown only).
    /// Whole-string events often duplicate or drop glyphs in Electron / web fields.
    public static func typeText(_ text: String) {
        guard !text.isEmpty else { return }
        for ch in text {
            let piece = String(ch)
            var utf16 = Array(piece.utf16)
            utf16.withUnsafeMutableBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) else { return }
                markAsOurs(down)
                down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
                down.post(tap: .cgSessionEventTap)
            }
            usleep(3_000)
        }
    }

    /// Replace the last `deleteCount` characters with `newText`.
    public static func replaceCharacters(deleteCount: Int, with newText: String) {
        isSynthesizing = true
        defer {
            usleep(5_000)
            isSynthesizing = false
        }
        deleteBackward(times: deleteCount)
        usleep(12_000)
        typeText(newText)
    }

    public static func postKey(keyCode: CGKeyCode, keyDown: Bool, flags: CGEventFlags = []) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: keyDown) else {
            return
        }
        event.flags = flags
        markAsOurs(event)
        event.post(tap: .cgSessionEventTap)
    }
}
