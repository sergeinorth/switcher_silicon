import ApplicationServices
import Foundation

/// Read/replace selected text via Accessibility when the focused element supports it.
public enum SelectedText {
    public enum Probe: Sendable {
        /// Focused element answered: nothing selected.
        case empty
        /// Non-empty selected text from AX.
        case text(String)
        /// No usable AX focus — caller may fall back to ⌘C.
        case unknown
    }

    public static func probe() -> Probe {
        guard let element = focusedElement() else { return .unknown }

        var selectedValue: CFTypeRef?
        let selectedErr = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedValue
        )
        if selectedErr == .success {
            let text = selectedValue as? String ?? ""
            return text.isEmpty ? .empty : .text(text)
        }

        var rangeValue: CFTypeRef?
        let rangeErr = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        )
        if rangeErr == .success, let rangeValue {
            var cfRange = CFRange(location: 0, length: 0)
            if AXValueGetValue(rangeValue as! AXValue, .cfRange, &cfRange) {
                return cfRange.length == 0 ? .empty : .unknown
            }
        }

        return .unknown
    }

    /// Replace current selection in-place. Returns false if the element rejects the write.
    @discardableResult
    public static func replaceAX(_ text: String) -> Bool {
        guard let element = focusedElement() else { return false }
        let err = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        return err == .success
    }

    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        guard err == .success, let focused else { return nil }
        return (focused as! AXUIElement)
    }
}
