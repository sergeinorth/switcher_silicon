import Foundation

public struct Hotkey: Codable, Equatable, Sendable {
    public var keyCode: UInt16
    public var modifiers: UInt64

    public static let none = Hotkey(keyCode: 0xFFFF, modifiers: 0)

    /// Left Option tap (modifier-only trigger handled specially).
    public static let leftOption = Hotkey(keyCode: 0xFFFF, modifiers: 1 << 19) // option alternate

    public var isUnset: Bool { keyCode == 0xFFFF && modifiers == 0 }

    public init(keyCode: UInt16, modifiers: UInt64) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public struct SoundMask: OptionSet, Codable, Equatable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let switchToRussian = SoundMask(rawValue: 1 << 0)
    public static let switchToEnglish = SoundMask(rawValue: 1 << 1)
    public static let autoConvert = SoundMask(rawValue: 1 << 2)
    public static let undo = SoundMask(rawValue: 1 << 3)
    public static let selectionConvert = SoundMask(rawValue: 1 << 4)
    public static let all: SoundMask = [
        .switchToRussian, .switchToEnglish, .autoConvert, .undo, .selectionConvert,
    ]
}

public struct UserRule: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var pattern: String
    public var isRegex: Bool
    public var shouldSwitch: Bool
    public var isActive: Bool

    public init(
        id: UUID = UUID(),
        pattern: String,
        isRegex: Bool = false,
        shouldSwitch: Bool,
        isActive: Bool = true
    ) {
        self.id = id
        self.pattern = pattern
        self.isRegex = isRegex
        self.shouldSwitch = shouldSwitch
        self.isActive = isActive
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var russianLayoutID: String
    public var englishLayoutID: String
    public var useOptionTrigger: Bool
    public var hotkeyUndo: Hotkey
    public var hotkeyToggleAutocorrection: Hotkey
    public var hotkeyChangeCase: Hotkey
    public var sounds: SoundMask
    public var isSoundOn: Bool
    public var isAutocorrectionActive: Bool
    public var cancelNextWordAfterManualSwitch: Bool
    public var noAutoconvertAfterTabOrEnter: Bool
    public var rememberLayoutPerApp: Bool
    public var excludedApps: [String]
    public var userRules: [UserRule]
    public var launchesOnStartup: Bool

    public static let `default` = AppSettings(
        russianLayoutID: "",
        englishLayoutID: "",
        useOptionTrigger: true,
        hotkeyUndo: Hotkey(keyCode: 0x33, modifiers: (1 << 20) | (1 << 19)), // Cmd+Opt+Delete placeholder
        hotkeyToggleAutocorrection: .none,
        hotkeyChangeCase: .none,
        sounds: .all,
        isSoundOn: true,
        isAutocorrectionActive: true,
        cancelNextWordAfterManualSwitch: true,
        noAutoconvertAfterTabOrEnter: false,
        rememberLayoutPerApp: true,
        excludedApps: [],
        userRules: [],
        launchesOnStartup: true
    )
}

public enum SettingsStore {
    public static let suiteName = "com.sergei.SwitcherSilicon"
    private static let key = "appSettings"

    public static func load() -> AppSettings {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        guard let data = defaults.data(forKey: key) else {
            return .default
        }
        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            return .default
        }
    }

    public static func save(_ settings: AppSettings) {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: key)
        }
    }
}
