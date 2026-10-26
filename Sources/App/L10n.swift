import Engine
import Foundation

enum L10n {
    static func t(_ key: Key, _ lang: UILanguage) -> String {
        switch lang {
        case .russian: return key.ru
        case .english: return key.en
        }
    }

    enum Key {
        case layout(String)
        case accessibilityOK
        case accessibilityNO
        case inputMonitoringOK
        case inputMonitoringNO
        case eventTapOK
        case eventTapNO
        case autoOn
        case autoOff
        case spellOn
        case spellOff
        case soundOn
        case soundOff
        case soundPicker
        case launchOn
        case launchOff
        case undoLast
        case diagnostics
        case openInputMonitoring
        case openAccessibility
        case excludeApp
        case quit
        case language
        case soundToRussian
        case soundToEnglish
        case soundAuto
        case soundUndo
        case soundSelection
        case soundReset
        case openLog
        case later
        case permTitle
        case permBody
        case diagHint
        case pauseOn
        case pauseOff
        case hotkeys
        case hotkeyConvert
        case hotkeyTeach
        case hotkeyPause
        case hotkeyUndo
        case pauseDuration
        case pause60
        case pause120
        case pause300
        case dictionary
        case dictIgnored
        case dictReplacements
        case dictAddIgnore
        case dictAddReplacement
        case dictEmpty
        case dictDelete
        case toastLayout
        case toastSpell
        case toastTeachApply
        case toastManual
        case toastSelection
        case toastIgnore
        case toastTeach
        case toastTeachUndo
        case toastPauseOn
        case toastPauseOff
        case toastPauseDetail(Int)
        case promptIgnoreTitle
        case promptIgnoreBody
        case promptReplaceTitle
        case promptReplaceFrom
        case promptReplaceTo
        case cancel
        case add

        var ru: String {
            switch self {
            case let .layout(code): return "Раскладка: \(code)"
            case .accessibilityOK: return "Универсальный доступ: ок"
            case .accessibilityNO: return "Универсальный доступ: НЕТ"
            case .inputMonitoringOK: return "Мониторинг ввода: ок"
            case .inputMonitoringNO: return "Мониторинг ввода: НЕТ"
            case .eventTapOK: return "Event tap: ок"
            case .eventTapNO: return "Event tap: НЕТ"
            case .autoOn: return "Автоконвертация: вкл"
            case .autoOff: return "Автоконвертация: выкл"
            case .spellOn: return "Автоопечатки: вкл"
            case .spellOff: return "Автоопечатки: выкл"
            case .soundOn: return "Звуки: вкл"
            case .soundOff: return "Звуки: выкл"
            case .soundPicker: return "Выбор звуков"
            case .launchOn: return "Запуск при входе: вкл"
            case .launchOff: return "Запуск при входе: выкл"
            case .undoLast: return "Отменить (запомнить слово)"
            case .diagnostics: return "Диагностика…"
            case .openInputMonitoring: return "Открыть Мониторинг ввода…"
            case .openAccessibility: return "Открыть Универсальный доступ…"
            case .excludeApp: return "Исключить текущее приложение"
            case .quit: return "Выйти"
            case .language: return "Язык интерфейса"
            case .soundToRussian: return "На русский"
            case .soundToEnglish: return "На английский"
            case .soundAuto: return "Автоконвертация"
            case .soundUndo: return "Отмена / промах"
            case .soundSelection: return "Выделение"
            case .soundReset: return "Сбросить по умолчанию"
            case .openLog: return "Открыть лог"
            case .later: return "Позже"
            case .permTitle: return "Нужны два разрешения"
            case .permBody: return """
                1) Конфиденциальность → Мониторинг ввода → включи SwitcherSilicon
                2) Конфиденциальность → Универсальный доступ → включи SwitcherSilicon

                Если галочка уже стоит, выключи и включи снова.
                Добавь через «+» файл: /Applications/SwitcherSilicon.app

                Пока в менюшке «!» — конвертация не работает.
                """
            case .diagHint: return """
                Нужны: Мониторинг ввода + Универсальный доступ для /Applications/SwitcherSilicon.app
                RuSwitcher держи выключенным.
                Лишнее автоисправление: Option (или ⌘⌥Z) — слово больше не трогаем.
                Своя замена: опечатка → поправь → Option+Shift; снова Option+Shift — отменить teach.
                Пауза: оба Shift (1 мин).
                """
            case .pauseOn: return "Пауза: вкл"
            case .pauseOff: return "Пауза: выкл"
            case .hotkeys: return "Горячие клавиши"
            case .hotkeyConvert: return "Конвертация / отмена"
            case .hotkeyTeach: return "Teach / отмена teach"
            case .hotkeyPause: return "Пауза"
            case .hotkeyUndo: return "Отмена в меню: ⌘⌥Z"
            case .pauseDuration: return "Длительность паузы"
            case .pause60: return "1 минута"
            case .pause120: return "2 минуты"
            case .pause300: return "5 минут"
            case .dictionary: return "Свои замены и исключения"
            case .dictIgnored: return "Исключения (не трогать)"
            case .dictReplacements: return "Замены"
            case .dictAddIgnore: return "Добавить исключение…"
            case .dictAddReplacement: return "Добавить замену…"
            case .dictEmpty: return "(пусто)"
            case .dictDelete: return "Удалить"
            case .toastLayout: return "Раскладка"
            case .toastSpell: return "Опечатка"
            case .toastTeachApply: return "Своя замена"
            case .toastManual: return "Конвертация"
            case .toastSelection: return "Выделение"
            case .toastIgnore: return "Исключено"
            case .toastTeach: return "Запомнили замену"
            case .toastTeachUndo: return "Teach отменён"
            case .toastPauseOn: return "Пауза"
            case .toastPauseOff: return "Пауза снята"
            case let .toastPauseDetail(sec): return "\(sec) сек"
            case .promptIgnoreTitle: return "Исключение"
            case .promptIgnoreBody: return "Слово, которое не трогать:"
            case .promptReplaceTitle: return "Своя замена"
            case .promptReplaceFrom: return "Было (опечатка):"
            case .promptReplaceTo: return "Стало:"
            case .cancel: return "Отмена"
            case .add: return "Добавить"
            }
        }

        var en: String {
            switch self {
            case let .layout(code): return "Layout: \(code)"
            case .accessibilityOK: return "Accessibility: ok"
            case .accessibilityNO: return "Accessibility: NO"
            case .inputMonitoringOK: return "Input Monitoring: ok"
            case .inputMonitoringNO: return "Input Monitoring: NO"
            case .eventTapOK: return "Event tap: ok"
            case .eventTapNO: return "Event tap: NO"
            case .autoOn: return "Auto-convert: on"
            case .autoOff: return "Auto-convert: off"
            case .spellOn: return "Spell fix: on"
            case .spellOff: return "Spell fix: off"
            case .soundOn: return "Sounds: on"
            case .soundOff: return "Sounds: off"
            case .soundPicker: return "Sound picker"
            case .launchOn: return "Launch at login: on"
            case .launchOff: return "Launch at login: off"
            case .undoLast: return "Undo (remember word)"
            case .diagnostics: return "Diagnostics…"
            case .openInputMonitoring: return "Open Input Monitoring…"
            case .openAccessibility: return "Open Accessibility…"
            case .excludeApp: return "Exclude current app"
            case .quit: return "Quit"
            case .language: return "UI language"
            case .soundToRussian: return "To Russian"
            case .soundToEnglish: return "To English"
            case .soundAuto: return "Auto-convert"
            case .soundUndo: return "Undo / miss"
            case .soundSelection: return "Selection"
            case .soundReset: return "Reset to defaults"
            case .openLog: return "Open log"
            case .later: return "Later"
            case .permTitle: return "Two permissions required"
            case .permBody: return """
                1) Privacy → Input Monitoring → enable SwitcherSilicon
                2) Privacy → Accessibility → enable SwitcherSilicon

                If already checked, turn off and on again.
                Add via “+”: /Applications/SwitcherSilicon.app

                While the menu shows “!”, conversion will not work.
                """
            case .diagHint: return """
                Required: Input Monitoring + Accessibility for /Applications/SwitcherSilicon.app
                Keep RuSwitcher disabled.
                Wrong auto-fix: Option (or ⌘⌥Z) — we remember the word and leave it alone.
                Custom fix: typo → correct it → Option+Shift; Option+Shift again undoes last teach.
                Pause: both Shifts (1 min).
                """
            case .pauseOn: return "Pause: on"
            case .pauseOff: return "Pause: off"
            case .hotkeys: return "Hotkeys"
            case .hotkeyConvert: return "Convert / undo"
            case .hotkeyTeach: return "Teach / undo teach"
            case .hotkeyPause: return "Pause"
            case .hotkeyUndo: return "Menu undo: ⌘⌥Z"
            case .pauseDuration: return "Pause duration"
            case .pause60: return "1 minute"
            case .pause120: return "2 minutes"
            case .pause300: return "5 minutes"
            case .dictionary: return "Custom fixes & exclusions"
            case .dictIgnored: return "Exclusions (leave alone)"
            case .dictReplacements: return "Replacements"
            case .dictAddIgnore: return "Add exclusion…"
            case .dictAddReplacement: return "Add replacement…"
            case .dictEmpty: return "(empty)"
            case .dictDelete: return "Delete"
            case .toastLayout: return "Layout"
            case .toastSpell: return "Spell"
            case .toastTeachApply: return "Custom fix"
            case .toastManual: return "Convert"
            case .toastSelection: return "Selection"
            case .toastIgnore: return "Excluded"
            case .toastTeach: return "Remembered fix"
            case .toastTeachUndo: return "Teach undone"
            case .toastPauseOn: return "Paused"
            case .toastPauseOff: return "Pause cleared"
            case let .toastPauseDetail(sec): return "\(sec) sec"
            case .promptIgnoreTitle: return "Exclusion"
            case .promptIgnoreBody: return "Word to leave alone:"
            case .promptReplaceTitle: return "Custom replacement"
            case .promptReplaceFrom: return "From (typo):"
            case .promptReplaceTo: return "To:"
            case .cancel: return "Cancel"
            case .add: return "Add"
            }
        }
    }
}
