import AppKit
import Engine
import Platform

@MainActor
final class StatusBarController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let orchestrator: LayoutOrchestrator
    private let inputSources = InputSourceManager()
    private let previewPlayer: SoundPlayer
    private var settings: AppSettings
    private var flashToken = 0
    private var layoutPoll: Timer?
    private var lastTitle = ""

    init(orchestrator: LayoutOrchestrator) {
        self.orchestrator = orchestrator
        self.settings = orchestrator.currentSettings
        self.previewPlayer = SoundPlayer(settings: orchestrator.currentSettings)
        if let button = item.button {
            button.toolTip = "Switcher Silicon"
        }
        refreshLayoutTitle()
        rebuildMenu()
        inputSources.observeLayoutChanges { [weak self] in
            Task { @MainActor in
                self?.refreshLayoutTitle()
            }
        }
        layoutPoll = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshLayoutTitle()
            }
        }
        orchestrator.onStatusChange = { [weak self] status in
            Task { @MainActor in
                self?.reflectStatus(status)
            }
        }
    }

    func refreshPermissionState() {
        lastTitle = ""
        refreshLayoutTitle()
        rebuildMenu()
    }

    private func layoutTitle() -> String {
        if !orchestrator.isTapActive { return "!" }
        return inputSources.isCurrentRussian ? "РУ" : "EN"
    }

    private func refreshLayoutTitle() {
        let title = layoutTitle()
        guard title != lastTitle else { return }
        lastTitle = title
        item.button?.title = title
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "Switcher Silicon", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

        let layoutItem = NSMenuItem(
            title: "Раскладка: \(inputSources.isCurrentRussian ? "РУ" : "EN")",
            action: nil,
            keyEquivalent: ""
        )
        layoutItem.isEnabled = false
        menu.addItem(layoutItem)

        let axItem = NSMenuItem(
            title: AccessibilityPermission.isAXTrusted ? "Универсальный доступ: ок" : "Универсальный доступ: НЕТ",
            action: nil,
            keyEquivalent: ""
        )
        axItem.isEnabled = false
        menu.addItem(axItem)

        let listenItem = NSMenuItem(
            title: AccessibilityPermission.canListenEvents ? "Мониторинг ввода: ок" : "Мониторинг ввода: НЕТ",
            action: nil,
            keyEquivalent: ""
        )
        listenItem.isEnabled = false
        menu.addItem(listenItem)

        let tapItem = NSMenuItem(
            title: orchestrator.isTapActive ? "Event tap: ок" : "Event tap: НЕТ",
            action: nil,
            keyEquivalent: ""
        )
        tapItem.isEnabled = false
        menu.addItem(tapItem)

        menu.addItem(.separator())

        let autoItem = NSMenuItem(
            title: settings.isAutocorrectionActive ? "Автоконвертация: вкл" : "Автоконвертация: выкл",
            action: #selector(toggleAuto),
            keyEquivalent: ""
        )
        autoItem.target = self
        menu.addItem(autoItem)

        let spellItem = NSMenuItem(
            title: settings.isSpellAutocorrectActive ? "Автоопечатки: вкл" : "Автоопечатки: выкл",
            action: #selector(toggleSpell),
            keyEquivalent: ""
        )
        spellItem.target = self
        menu.addItem(spellItem)

        let soundItem = NSMenuItem(
            title: settings.isSoundOn ? "Звуки: вкл" : "Звуки: выкл",
            action: #selector(toggleSound),
            keyEquivalent: ""
        )
        soundItem.target = self
        menu.addItem(soundItem)

        let soundsMenu = NSMenuItem(title: "Выбор звуков", action: nil, keyEquivalent: "")
        soundsMenu.submenu = buildSoundsSubmenu()
        menu.addItem(soundsMenu)

        menu.addItem(.separator())

        let undoItem = NSMenuItem(title: "Отменить последнюю конвертацию", action: #selector(undo), keyEquivalent: "z")
        undoItem.keyEquivalentModifierMask = [.command, .option]
        undoItem.target = self
        menu.addItem(undoItem)

        let caseItem = NSMenuItem(title: "Сменить регистр", action: #selector(changeCase), keyEquivalent: "")
        caseItem.target = self
        menu.addItem(caseItem)

        menu.addItem(.separator())

        let diagItem = NSMenuItem(title: "Диагностика…", action: #selector(showDiagnostics), keyEquivalent: "")
        diagItem.target = self
        menu.addItem(diagItem)

        let listenSettings = NSMenuItem(title: "Открыть Мониторинг ввода…", action: #selector(openInputMonitoring), keyEquivalent: "")
        listenSettings.target = self
        menu.addItem(listenSettings)

        let accessItem = NSMenuItem(title: "Открыть Универсальный доступ…", action: #selector(openAccessibility), keyEquivalent: "")
        accessItem.target = self
        menu.addItem(accessItem)

        let excludeItem = NSMenuItem(title: "Исключить текущее приложение", action: #selector(excludeFrontApp), keyEquivalent: "")
        excludeItem.target = self
        menu.addItem(excludeItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Выйти", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
    }

    private func buildSoundsSubmenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(soundRoleMenu(
            title: "На русский",
            current: settings.soundPrefs.switchToRussian,
            role: "russian"
        ))
        menu.addItem(soundRoleMenu(
            title: "На английский",
            current: settings.soundPrefs.switchToEnglish,
            role: "english"
        ))
        menu.addItem(soundRoleMenu(
            title: "Автоконвертация",
            current: settings.soundPrefs.autoConvert,
            role: "auto"
        ))
        menu.addItem(soundRoleMenu(
            title: "Отмена / промах",
            current: settings.soundPrefs.undo,
            role: "undo"
        ))
        menu.addItem(soundRoleMenu(
            title: "Выделение",
            current: settings.soundPrefs.selectionConvert,
            role: "selection"
        ))
        menu.addItem(.separator())
        let reset = NSMenuItem(title: "Сбросить по умолчанию", action: #selector(resetSounds), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)
        return menu
    }

    private func soundRoleMenu(title: String, current: String, role: String) -> NSMenuItem {
        let item = NSMenuItem(title: "\(title): \(current)", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for name in SoundPrefs.catalog {
            let opt = NSMenuItem(title: name, action: #selector(selectSound(_:)), keyEquivalent: "")
            opt.target = self
            opt.representedObject = "\(role)|\(name)"
            opt.state = (name == current) ? .on : .off
            sub.addItem(opt)
        }
        item.submenu = sub
        return item
    }

    private func reflectStatus(_ status: String) {
        if status.hasPrefix("auto:") || status.hasPrefix("manual:") {
            flashToken += 1
            let token = flashToken
            lastTitle = "✓"
            item.button?.title = "✓"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, self.flashToken == token else { return }
                self.lastTitle = ""
                self.refreshLayoutTitle()
            }
        } else {
            lastTitle = ""
            refreshLayoutTitle()
        }
        rebuildMenu()
    }

    @objc private func toggleAuto() {
        settings.isAutocorrectionActive.toggle()
        persist()
    }

    @objc private func toggleSpell() {
        settings.isSpellAutocorrectActive.toggle()
        persist()
    }

    @objc private func toggleSound() {
        settings.isSoundOn.toggle()
        persist()
    }

    @objc private func selectSound(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        let parts = raw.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        let role = parts[0]
        let name = parts[1]
        switch role {
        case "russian": settings.soundPrefs.switchToRussian = name
        case "english": settings.soundPrefs.switchToEnglish = name
        case "auto": settings.soundPrefs.autoConvert = name
        case "undo": settings.soundPrefs.undo = name
        case "selection": settings.soundPrefs.selectionConvert = name
        default: return
        }
        previewPlayer.settings = settings
        previewPlayer.preview(named: name)
        persist()
    }

    @objc private func resetSounds() {
        settings.soundPrefs = .default
        persist()
    }

    private func persist() {
        orchestrator.reloadSettings(settings)
        settings = orchestrator.currentSettings
        previewPlayer.settings = settings
        rebuildMenu()
    }

    @objc private func undo() {
        orchestrator.undoLastConversion()
    }

    @objc private func changeCase() {
        orchestrator.changeCaseOfBufferOrSelection()
    }

    @objc private func openAccessibility() {
        AccessibilityPermission.openAccessibilitySettings()
    }

    @objc private func openInputMonitoring() {
        AccessibilityPermission.openInputMonitoringSettings()
    }

    @objc private func showDiagnostics() {
        let diag = orchestrator.diagnostics()
        let alert = NSAlert()
        alert.messageText = "Switcher Silicon"
        alert.informativeText = diag
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Открыть лог")
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            let log = NSHomeDirectory() + "/Library/Logs/SwitcherSilicon.log"
            NSWorkspace.shared.open(URL(fileURLWithPath: log))
        }
    }

    @objc private func excludeFrontApp() {
        guard let bundle = FrontmostApp.bundleID else { return }
        if !settings.excludedApps.contains(bundle) {
            settings.excludedApps.append(bundle)
            persist()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
