import AppKit
import Carbon

public enum EventSynth {
    private static let sourceID: Int64 = 0x53575349 // 'SWSI'

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
        }
    }

    public static func typeText(_ text: String) {
        guard !text.isEmpty else { return }
        // Prefer unicode string events — works in most Cocoa / Electron apps without clipboard.
        var utf16 = Array(text.utf16)
        utf16.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            if let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) {
                markAsOurs(down)
                down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
                down.post(tap: .cghidEventTap)
            }
            if let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
                markAsOurs(up)
                up.post(tap: .cghidEventTap)
            }
        }
    }

    public static func replaceLastWord(originalLength: Int, with newText: String) {
        deleteBackward(times: originalLength)
        // Small delay helps some apps settle after backspaces.
        usleep(8_000)
        typeText(newText)
    }

    public static func postKey(keyCode: CGKeyCode, keyDown: Bool, flags: CGEventFlags = []) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: keyDown) else {
            return
        }
        event.flags = flags
        markAsOurs(event)
        event.post(tap: .cghidEventTap)
    }
}
