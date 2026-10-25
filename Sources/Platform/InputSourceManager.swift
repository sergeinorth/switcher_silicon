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
        // Prefer the keyboard *layout* source — IME wrappers can hide the real EN/RU map.
        if let layout = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
           let sid = id(of: layout), !sid.isEmpty
        {
            return sid
        }
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return ""
        }
        return id(of: source) ?? ""
    }

    public var isCurrentRussian: Bool {
        isRussianID(currentSourceID) || isRussianName(currentSourceName)
    }

    public var currentSourceName: String? {
        if let layout = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
           let n = name(of: layout)
        {
            return n
        }
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        return name(of: source)
    }

    public func isRussianID(_ sourceID: String) -> Bool {
        let id = sourceID.lowercased()
        return id.contains("russian") || id.contains("cyrillic") || id.contains("ukrain")
            || id.contains("belarus") || id.contains("bulgar") || id.contains("serbian")
            || id.contains("kazakh") || id.contains("kyrgyz") || id.contains("tajik")
            || id.contains("turkmen") || id.contains("uzbek") || id.contains("mongolian")
    }

    private func isRussianName(_ name: String?) -> Bool {
        guard let name = name?.lowercased() else { return false }
        return name.contains("рус") || name.contains("russian") || name.contains("укра")
            || name.contains("бел") || name.contains("кырг") || name.contains("қаз")
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
        guard !sourceID.isEmpty else { return false }
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return false
        }
        guard let source = list.first(where: { id(of: $0) == sourceID }) else {
            return false
        }
        // No usleep here — blocking the event-tap/main thread dropped the next Space convert.
        return TISSelectInputSource(source) == noErr
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
