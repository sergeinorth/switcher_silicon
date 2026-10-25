import AppKit
import Carbon

public enum EventSynth {
    private static let sourceID: Int64 = 0x53575349 // 'SWSI'

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
            usleep(1_000)
        }
    }

    public static func typeText(_ text: String) {
        guard !text.isEmpty else { return }
        // Batch whole string in one unicode event — much faster, less tap starvation.
        var utf16 = Array(text.utf16)
        utf16.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) else { return }
            markAsOurs(down)
            down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
            down.post(tap: .cghidEventTap)
        }
    }

    public static func replaceCharacters(deleteCount: Int, with newText: String) {
        isSynthesizing = true
        defer {
            usleep(3_000)
            isSynthesizing = false
        }
        AppLog.line("replace delete=\(deleteCount) text=\(newText)")
        deleteBackward(times: deleteCount)
        usleep(5_000)
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
