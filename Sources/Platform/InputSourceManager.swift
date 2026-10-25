import AppKit
import Carbon
import Engine

public final class InputSourceManager: @unchecked Sendable {
    public init() {}

    /// Fires on the main queue when the user (or we) change the keyboard layout.
    public func observeLayoutChanges(_ handler: @escaping @Sendable () -> Void) {
        DistributedNotificationCenter.default.addObserver(
            forName: NSNotification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil,
            queue: .main
        ) { _ in
            handler()
        }
    }

    public var currentSourceID: String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return ""
        }
        return id(of: source) ?? ""
    }

    public var isCurrentRussian: Bool {
        let id = currentSourceID.lowercased()
        if id.contains("russian") || id.contains("cyrillic") || id.contains("ukrain")
            || id.contains("belarus") || id.contains("bulgar") || id.contains("serbian")
        {
            return true
        }
        // Fallback: localized name
        if let name = currentSourceName?.lowercased() {
            return name.contains("рус") || name.contains("russian") || name.contains("укра")
        }
        return false
    }

    public var currentSourceName: String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        return name(of: source)
    }

    public func availableSources() -> [(id: String, name: String)] {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        return list.compactMap { source in
            guard let sid = id(of: source), let name = name(of: source) else { return nil }
            let category = property(source, kTISPropertyInputSourceCategory) as? String
            guard category == (kTISCategoryKeyboardInputSource as String) else { return nil }
            let enabled = property(source, kTISPropertyInputSourceIsEnabled) as? Bool ?? false
            guard enabled else { return nil }
            return (sid, name)
        }
    }

    public func preferRussianID() -> String? {
        availableSources().first { $0.id.lowercased().contains("russian") }?.id
            ?? availableSources().first { $0.name.lowercased().contains("russian") }?.id
    }

    public func preferEnglishID() -> String? {
        availableSources().first {
            let id = $0.id.lowercased()
            return id.contains("abc") || id.contains("us") || id.contains("british") || id.contains("australian")
        }?.id
        ?? availableSources().first { $0.name.lowercased().contains("abc") || $0.name.lowercased().contains("u.s.") }?.id
    }

    @discardableResult
    public func select(sourceID: String) -> Bool {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return false
        }
        guard let source = list.first(where: { id(of: $0) == sourceID }) else {
            return false
        }
        let status = TISSelectInputSource(source)
        return status == noErr
    }

    @discardableResult
    public func switchToRussian(preferredID: String?) -> Bool {
        if let preferredID, !preferredID.isEmpty, select(sourceID: preferredID) {
            return true
        }
        if let id = preferRussianID() {
            return select(sourceID: id)
        }
        return false
    }

    @discardableResult
    public func switchToEnglish(preferredID: String?) -> Bool {
        if let preferredID, !preferredID.isEmpty, select(sourceID: preferredID) {
            return true
        }
        if let id = preferEnglishID() {
            return select(sourceID: id)
        }
        return false
    }

    @discardableResult
    public func toggleLanguage(settings: AppSettings) -> Bool {
        if isCurrentRussian {
            return switchToEnglish(preferredID: settings.englishLayoutID)
        }
        return switchToRussian(preferredID: settings.russianLayoutID)
    }

    private func id(of source: TISInputSource) -> String? {
        property(source, kTISPropertyInputSourceID) as? String
    }

    private func name(of source: TISInputSource) -> String? {
        property(source, kTISPropertyLocalizedName) as? String
    }

    private func property(_ source: TISInputSource, _ key: CFString) -> AnyObject? {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    }
}
