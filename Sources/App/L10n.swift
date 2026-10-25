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
        case changeCase
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
            case .undoLast: return "Отменить последнюю конвертацию"
            case .changeCase: return "Сменить регистр"
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
                """
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
            case .undoLast: return "Undo last conversion"
            case .changeCase: return "Change case"
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
                """
            }
        }
    }
}
