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
            // TextEdit / Chrome drop backspaces if they arrive faster than ~1ms.
            usleep(2_500)
        }
    }

    /// Deletes the previous word in one shot (Option+Delete). More reliable than N backspaces.
    public static func deleteBackwardWord() {
        postKey(keyCode: 51, keyDown: true, flags: .maskAlternate)
        postKey(keyCode: 51, keyDown: false, flags: .maskAlternate)
        usleep(4_000)
    }

    public static func typeText(_ text: String) {
        guard !text.isEmpty else { return }
        var utf16 = Array(text.utf16)
        utf16.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) else { return }
            markAsOurs(down)
            down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
            down.post(tap: .cghidEventTap)
            if let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
                markAsOurs(up)
                up.post(tap: .cghidEventTap)
            }
        }
    }

    /// - Parameter useWordDelete: Option+Delete once instead of N backspaces.
    /// - Parameter trailingSpaceInField: Space already typed — remove it after the word.
    public static func replaceCharacters(
        deleteCount: Int,
        with newText: String,
        useWordDelete: Bool = false,
        trailingSpaceInField: Bool = false
    ) {
        isSynthesizing = true
        defer {
            usleep(2_000)
            isSynthesizing = false
        }
        AppLog.line(
            "replace delete=\(deleteCount) text=\(newText) wordDel=\(useWordDelete) sp=\(trailingSpaceInField)"
        )
        // Let the last typed key commit into the target field before we erase.
        usleep(12_000)
        if useWordDelete, deleteCount > 0 {
            deleteBackwardWord()
            if trailingSpaceInField {
                deleteBackward(times: 1)
            }
        } else {
            deleteBackward(times: deleteCount)
        }
        usleep(3_000)
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
