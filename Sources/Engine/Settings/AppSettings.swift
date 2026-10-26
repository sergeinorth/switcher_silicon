import Foundation

public struct Hotkey: Codable, Equatable, Sendable {
    public var keyCode: UInt16
    public var modifiers: UInt64

    public static let none = Hotkey(keyCode: 0xFFFF, modifiers: 0)

    /// Left Option tap (modifier-only trigger handled specially).
    public static let leftOption = Hotkey(keyCode: 0xFFFF, modifiers: 1 << 19) // option alternate

    /// ⌘⌥Z — menu undo.
    public static let undoDefault = Hotkey(keyCode: 6, modifiers: (1 << 20) | (1 << 19)) // Z + cmd + opt

    public var isUnset: Bool { keyCode == 0xFFFF && modifiers == 0 }

    public init(keyCode: UInt16, modifiers: UInt64) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var hasCommand: Bool { modifiers & (1 << 20) != 0 }
    public var hasOption: Bool { modifiers & (1 << 19) != 0 }
    public var hasShift: Bool { modifiers & (1 << 17) != 0 }
    public var hasControl: Bool { modifiers & (1 << 18) != 0 }
}

/// Modifier-only chords used by the event tap (not regular key combos).
public enum ModifierChord: String, Codable, Sendable, CaseIterable {
    case eitherOption
    case leftOption
    case rightOption
    case optionShift
    case leftOptionShift
    case rightOptionShift
    case bothShifts
    case disabled

    public func label(language: UILanguage) -> String {
        switch language {
        case .russian:
            switch self {
            case .eitherOption: return "Option (любой)"
            case .leftOption: return "Левый Option"
            case .rightOption: return "Правый Option"
            case .optionShift: return "Option+Shift"
            case .leftOptionShift: return "Левый Option+Shift"
            case .rightOptionShift: return "Правый Option+Shift"
            case .bothShifts: return "Оба Shift"
            case .disabled: return "Выкл"
            }
        case .english:
            switch self {
            case .eitherOption: return "Option (either)"
            case .leftOption: return "Left Option"
            case .rightOption: return "Right Option"
            case .optionShift: return "Option+Shift"
            case .leftOptionShift: return "Left Option+Shift"
            case .rightOptionShift: return "Right Option+Shift"
            case .bothShifts: return "Both Shifts"
            case .disabled: return "Off"
            }
        }
    }

    public var wantsShift: Bool {
        switch self {
        case .optionShift, .leftOptionShift, .rightOptionShift: return true
        default: return false
        }
    }

    public var isOptionBased: Bool {
        switch self {
        case .eitherOption, .leftOption, .rightOption,
             .optionShift, .leftOptionShift, .rightOptionShift:
            return true
        case .bothShifts, .disabled:
            return false
        }
    }

    /// `nil` = either side; 58 left, 61 right.
    public var requiredOptionKeyCode: UInt16? {
        switch self {
        case .leftOption, .leftOptionShift: return 58
        case .rightOption, .rightOptionShift: return 61
        default: return nil
        }
    }
}

public struct HotkeyPrefs: Codable, Equatable, Sendable {
    public var convert: ModifierChord
    public var teach: ModifierChord
    public var pause: ModifierChord
    public var undo: Hotkey
    /// Pause duration in seconds (both-shifts default).
    public var pauseSeconds: Double

    public static let `default` = HotkeyPrefs(
        convert: .eitherOption,
        teach: .optionShift,
        pause: .bothShifts,
        undo: .undoDefault,
        pauseSeconds: 60
    )
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

public struct SoundPrefs: Codable, Equatable, Sendable {
    public var switchToRussian: String
    public var switchToEnglish: String
    public var autoConvert: String
    public var undo: String
    public var selectionConvert: String

    public static let `default` = SoundPrefs(
        switchToRussian: "Tink",
        switchToEnglish: "Pop",
        autoConvert: "Glass",
        undo: "Bottle",
        selectionConvert: "Purr"
    )

    public static let catalog: [String] = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink",
    ]
}

public enum UILanguage: String, Codable, Sendable, CaseIterable {
    case russian
    case english

    public static var systemDefault: UILanguage {
        let langs = Locale.preferredLanguages.map { $0.lowercased() }
        if langs.contains(where: { $0.hasPrefix("ru") }) {
            return .russian
        }
        return .english
    }

    public var menuLabel: String {
        switch self {
        case .russian: return "Русский"
        case .english: return "English"
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var russianLayoutID: String
    public var englishLayoutID: String
    public var useOptionTrigger: Bool
    public var hotkeyUndo: Hotkey
    public var hotkeyToggleAutocorrection: Hotkey
    public var sounds: SoundMask
    public var isSoundOn: Bool
    public var soundPrefs: SoundPrefs
    public var isAutocorrectionActive: Bool
    /// Typo autocorrect (превет→привет). Off by default — conservative.
    public var isSpellAutocorrectActive: Bool
    public var cancelNextWordAfterManualSwitch: Bool
    public var noAutoconvertAfterTabOrEnter: Bool
    public var rememberLayoutPerApp: Bool
    public var excludedApps: [String]
    public var userRules: [UserRule]
    /// Words that must not be layout-converted or spell-fixed (lowercased).
    public var ignoredWords: [String]
    /// User-taught spell fixes: lowercase typo → preferred spelling.
    public var spellReplacements: [String: String]
    public var hotkeys: HotkeyPrefs
    public var launchesOnStartup: Bool
    /// Menu / alerts language (not keyboard layout).
    public var uiLanguage: UILanguage

    public static let `default` = AppSettings(
        russianLayoutID: "",
        englishLayoutID: "",
        useOptionTrigger: true,
        hotkeyUndo: Hotkey.undoDefault,
        hotkeyToggleAutocorrection: .none,
        sounds: .all,
        isSoundOn: true,
        soundPrefs: .default,
        isAutocorrectionActive: true,
        isSpellAutocorrectActive: false,
        cancelNextWordAfterManualSwitch: true,
        noAutoconvertAfterTabOrEnter: false,
        rememberLayoutPerApp: true,
        excludedApps: [],
        userRules: [],
        ignoredWords: [],
        spellReplacements: [:],
        hotkeys: .default,
        launchesOnStartup: false,
        uiLanguage: .systemDefault
    )

    public init(
        russianLayoutID: String,
        englishLayoutID: String,
        useOptionTrigger: Bool,
        hotkeyUndo: Hotkey,
        hotkeyToggleAutocorrection: Hotkey,
        sounds: SoundMask,
        isSoundOn: Bool,
        soundPrefs: SoundPrefs,
        isAutocorrectionActive: Bool,
        isSpellAutocorrectActive: Bool,
        cancelNextWordAfterManualSwitch: Bool,
        noAutoconvertAfterTabOrEnter: Bool,
        rememberLayoutPerApp: Bool,
        excludedApps: [String],
        userRules: [UserRule],
        ignoredWords: [String],
        spellReplacements: [String: String],
        hotkeys: HotkeyPrefs,
        launchesOnStartup: Bool,
        uiLanguage: UILanguage
    ) {
        self.russianLayoutID = russianLayoutID
        self.englishLayoutID = englishLayoutID
        self.useOptionTrigger = useOptionTrigger
        self.hotkeyUndo = hotkeyUndo
        self.hotkeyToggleAutocorrection = hotkeyToggleAutocorrection
        self.sounds = sounds
        self.isSoundOn = isSoundOn
        self.soundPrefs = soundPrefs
        self.isAutocorrectionActive = isAutocorrectionActive
        self.isSpellAutocorrectActive = isSpellAutocorrectActive
        self.cancelNextWordAfterManualSwitch = cancelNextWordAfterManualSwitch
        self.noAutoconvertAfterTabOrEnter = noAutoconvertAfterTabOrEnter
        self.rememberLayoutPerApp = rememberLayoutPerApp
        self.excludedApps = excludedApps
        self.userRules = userRules
        self.ignoredWords = ignoredWords
        self.spellReplacements = spellReplacements
        self.hotkeys = hotkeys
        self.launchesOnStartup = launchesOnStartup
        self.uiLanguage = uiLanguage
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.default
        russianLayoutID = try c.decodeIfPresent(String.self, forKey: .russianLayoutID) ?? d.russianLayoutID
        englishLayoutID = try c.decodeIfPresent(String.self, forKey: .englishLayoutID) ?? d.englishLayoutID
        useOptionTrigger = try c.decodeIfPresent(Bool.self, forKey: .useOptionTrigger) ?? d.useOptionTrigger
        hotkeyUndo = try c.decodeIfPresent(Hotkey.self, forKey: .hotkeyUndo) ?? d.hotkeyUndo
        hotkeyToggleAutocorrection = try c.decodeIfPresent(Hotkey.self, forKey: .hotkeyToggleAutocorrection) ?? d.hotkeyToggleAutocorrection
        sounds = try c.decodeIfPresent(SoundMask.self, forKey: .sounds) ?? d.sounds
        isSoundOn = try c.decodeIfPresent(Bool.self, forKey: .isSoundOn) ?? d.isSoundOn
        soundPrefs = try c.decodeIfPresent(SoundPrefs.self, forKey: .soundPrefs) ?? d.soundPrefs
        isAutocorrectionActive = try c.decodeIfPresent(Bool.self, forKey: .isAutocorrectionActive) ?? d.isAutocorrectionActive
        isSpellAutocorrectActive = try c.decodeIfPresent(Bool.self, forKey: .isSpellAutocorrectActive) ?? d.isSpellAutocorrectActive
        cancelNextWordAfterManualSwitch = try c.decodeIfPresent(Bool.self, forKey: .cancelNextWordAfterManualSwitch) ?? d.cancelNextWordAfterManualSwitch
        noAutoconvertAfterTabOrEnter = try c.decodeIfPresent(Bool.self, forKey: .noAutoconvertAfterTabOrEnter) ?? d.noAutoconvertAfterTabOrEnter
        rememberLayoutPerApp = try c.decodeIfPresent(Bool.self, forKey: .rememberLayoutPerApp) ?? d.rememberLayoutPerApp
        excludedApps = try c.decodeIfPresent([String].self, forKey: .excludedApps) ?? d.excludedApps
        userRules = try c.decodeIfPresent([UserRule].self, forKey: .userRules) ?? d.userRules
        ignoredWords = try c.decodeIfPresent([String].self, forKey: .ignoredWords) ?? d.ignoredWords
        spellReplacements = try c.decodeIfPresent([String: String].self, forKey: .spellReplacements) ?? d.spellReplacements
        hotkeys = try c.decodeIfPresent(HotkeyPrefs.self, forKey: .hotkeys) ?? d.hotkeys
        // Keep legacy undo field in sync with hotkeys.undo when loading old prefs.
        if c.contains(.hotkeys) == false, hotkeyUndo.keyCode != Hotkey.undoDefault.keyCode {
            hotkeys.undo = hotkeyUndo
        } else {
            hotkeyUndo = hotkeys.undo
        }
        launchesOnStartup = try c.decodeIfPresent(Bool.self, forKey: .launchesOnStartup) ?? d.launchesOnStartup
        uiLanguage = try c.decodeIfPresent(UILanguage.self, forKey: .uiLanguage) ?? d.uiLanguage
    }

    public var ignoredWordSet: Set<String> {
        Set(ignoredWords.map { $0.lowercased() })
    }
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
