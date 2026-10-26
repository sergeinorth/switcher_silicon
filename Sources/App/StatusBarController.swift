import AppKit
import Engine
import Platform

@MainActor
final class StatusBarController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let orchestrator: LayoutOrchestrator
    private let inputSources = InputSourceManager()
    private let previewPlayer: SoundPlayer
    private let toast = ActionToast()
    private var settings: AppSettings
    private var flashToken = 0
    private var layoutPoll: Timer?
    private var lastTitle = ""
    private var toastUndoKind = ""

    private var lang: UILanguage { settings.uiLanguage }

    init(orchestrator: LayoutOrchestrator) {
        self.orchestrator = orchestrator
        self.settings = orchestrator.currentSettings
        self.previewPlayer = SoundPlayer(settings: orchestrator.currentSettings)
        if let button = item.button {
            button.toolTip = "Switcher Silicon"
        }
        toast.onUndo = { [weak self] in
            self?.handleToastUndo()
        }
        refreshLayoutTitle()
        rebuildMenu()
        inputSources.observeLayoutChanges { [weak self] in
            Task { @MainActor in
                self?.orchestrator.noteExternalLayoutChange()
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
        orchestrator.onActionToast = { [weak self] title, detail in
            Task { @MainActor in
                self?.showToast(title: title, detail: detail)
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
        if orchestrator.isPaused {
            let sec = orchestrator.pauseRemainingSeconds
            return sec > 0 ? "⏸\(sec)" : "⏸"
        }
        return inputSources.isCurrentRussian ? "РУ" : "EN"
    }

    private func refreshLayoutTitle() {
        let title = layoutTitle()
        guard title != lastTitle else { return }
        lastTitle = title
        item.button?.title = title
    }

    private func s(_ key: L10n.Key) -> String {
        L10n.t(key, lang)
    }

    private func showToast(title: String, detail: String) {
        toastUndoKind = orchestrator.lastActionReason
        toast.show(title: title, detail: detail)
    }

    private func handleToastUndo() {
        switch toastUndoKind {
        case "teach":
            _ = orchestrator.undoLastTeach()
        case "pause":
            if orchestrator.isPaused {
                orchestrator.togglePause()
            }
        case "ignore":
            break
        default:
            orchestrator.undoLastConversion()
        }
        toastUndoKind = ""
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let l = lang

        let titleItem = NSMenuItem(title: "Switcher Silicon", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

        let layoutCode = inputSources.isCurrentRussian ? "РУ" : "EN"
        let layoutItem = NSMenuItem(title: s(.layout(layoutCode)), action: nil, keyEquivalent: "")
        layoutItem.isEnabled = false
        menu.addItem(layoutItem)

        let axItem = NSMenuItem(
            title: AccessibilityPermission.isAXTrusted ? s(.accessibilityOK) : s(.accessibilityNO),
            action: nil,
            keyEquivalent: ""
        )
        axItem.isEnabled = false
        menu.addItem(axItem)

        let listenItem = NSMenuItem(
            title: AccessibilityPermission.canListenEvents ? s(.inputMonitoringOK) : s(.inputMonitoringNO),
            action: nil,
            keyEquivalent: ""
        )
        listenItem.isEnabled = false
        menu.addItem(listenItem)

        let tapItem = NSMenuItem(
            title: orchestrator.isTapActive ? s(.eventTapOK) : s(.eventTapNO),
            action: nil,
            keyEquivalent: ""
        )
        tapItem.isEnabled = false
        menu.addItem(tapItem)

        menu.addItem(.separator())

        let pauseItem = NSMenuItem(
            title: orchestrator.isPaused ? s(.pauseOn) : s(.pauseOff),
            action: #selector(togglePause),
            keyEquivalent: ""
        )
        pauseItem.target = self
        menu.addItem(pauseItem)

        let autoItem = NSMenuItem(
            title: settings.isAutocorrectionActive ? s(.autoOn) : s(.autoOff),
            action: #selector(toggleAuto),
            keyEquivalent: ""
        )
        autoItem.target = self
        menu.addItem(autoItem)

        let spellItem = NSMenuItem(
            title: settings.isSpellAutocorrectActive ? s(.spellOn) : s(.spellOff),
            action: #selector(toggleSpell),
            keyEquivalent: ""
        )
        spellItem.target = self
        menu.addItem(spellItem)

        let soundItem = NSMenuItem(
            title: settings.isSoundOn ? s(.soundOn) : s(.soundOff),
            action: #selector(toggleSound),
            keyEquivalent: ""
        )
        soundItem.target = self
        menu.addItem(soundItem)

        let soundsMenu = NSMenuItem(title: s(.soundPicker), action: nil, keyEquivalent: "")
        soundsMenu.submenu = buildSoundsSubmenu()
        menu.addItem(soundsMenu)

        let launchItem = NSMenuItem(
            title: settings.launchesOnStartup ? s(.launchOn) : s(.launchOff),
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        menu.addItem(launchItem)

        let langMenu = NSMenuItem(title: s(.language), action: nil, keyEquivalent: "")
        let langSub = NSMenu()
        for option in UILanguage.allCases {
            let opt = NSMenuItem(title: option.menuLabel, action: #selector(selectUILanguage(_:)), keyEquivalent: "")
            opt.target = self
            opt.representedObject = option.rawValue
            opt.state = (option == l) ? .on : .off
            langSub.addItem(opt)
        }
        langMenu.submenu = langSub
        menu.addItem(langMenu)

        menu.addItem(.separator())

        let hotkeysItem = NSMenuItem(title: s(.hotkeys), action: nil, keyEquivalent: "")
        hotkeysItem.submenu = buildHotkeysSubmenu()
        menu.addItem(hotkeysItem)

        let dictItem = NSMenuItem(title: s(.dictionary), action: nil, keyEquivalent: "")
        dictItem.submenu = buildDictionarySubmenu()
        menu.addItem(dictItem)

        menu.addItem(.separator())

        let undoItem = NSMenuItem(title: s(.undoLast), action: #selector(undo), keyEquivalent: "z")
        undoItem.keyEquivalentModifierMask = [.command, .option]
        undoItem.target = self
        menu.addItem(undoItem)

        menu.addItem(.separator())

        let diagItem = NSMenuItem(title: s(.diagnostics), action: #selector(showDiagnostics), keyEquivalent: "")
        diagItem.target = self
        menu.addItem(diagItem)

        let listenSettings = NSMenuItem(title: s(.openInputMonitoring), action: #selector(openInputMonitoring), keyEquivalent: "")
        listenSettings.target = self
        menu.addItem(listenSettings)

        let accessItem = NSMenuItem(title: s(.openAccessibility), action: #selector(openAccessibility), keyEquivalent: "")
        accessItem.target = self
        menu.addItem(accessItem)

        let excludeItem = NSMenuItem(title: s(.excludeApp), action: #selector(excludeFrontApp), keyEquivalent: "")
        excludeItem.target = self
        menu.addItem(excludeItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: s(.quit), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
    }

    private func buildHotkeysSubmenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(chordMenu(title: s(.hotkeyConvert), current: settings.hotkeys.convert, role: "convert"))
        menu.addItem(chordMenu(title: s(.hotkeyTeach), current: settings.hotkeys.teach, role: "teach"))
        menu.addItem(chordMenu(title: s(.hotkeyPause), current: settings.hotkeys.pause, role: "pause", only: [.bothShifts, .disabled]))

        let duration = NSMenuItem(title: s(.pauseDuration), action: nil, keyEquivalent: "")
        let durationSub = NSMenu()
        for (secs, key) in [(60.0, L10n.Key.pause60), (120.0, .pause120), (300.0, .pause300)] {
            let opt = NSMenuItem(title: s(key), action: #selector(selectPauseDuration(_:)), keyEquivalent: "")
            opt.target = self
            opt.representedObject = secs
            opt.state = (abs(settings.hotkeys.pauseSeconds - secs) < 0.5) ? .on : .off
            durationSub.addItem(opt)
        }
        duration.submenu = durationSub
        menu.addItem(duration)

        let undoHint = NSMenuItem(title: s(.hotkeyUndo), action: nil, keyEquivalent: "")
        undoHint.isEnabled = false
        menu.addItem(undoHint)
        return menu
    }

    private func chordMenu(
        title: String,
        current: ModifierChord,
        role: String,
        only: [ModifierChord]? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: "\(title): \(current.label(language: lang))", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let options = only ?? ModifierChord.allCases
        for chord in options {
            let opt = NSMenuItem(
                title: chord.label(language: lang),
                action: #selector(selectChord(_:)),
                keyEquivalent: ""
            )
            opt.target = self
            opt.representedObject = "\(role)|\(chord.rawValue)"
            opt.state = (chord == current) ? .on : .off
            sub.addItem(opt)
        }
        item.submenu = sub
        return item
    }

    private func buildDictionarySubmenu() -> NSMenu {
        let menu = NSMenu()

        let ignoredHeader = NSMenuItem(title: s(.dictIgnored), action: nil, keyEquivalent: "")
        ignoredHeader.isEnabled = false
        menu.addItem(ignoredHeader)

        let ignored = settings.ignoredWords.sorted()
        if ignored.isEmpty {
            let empty = NSMenuItem(title: s(.dictEmpty), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for word in ignored.prefix(40) {
                let row = NSMenuItem(title: word, action: nil, keyEquivalent: "")
                let sub = NSMenu()
                let del = NSMenuItem(title: s(.dictDelete), action: #selector(deleteIgnored(_:)), keyEquivalent: "")
                del.target = self
                del.representedObject = word
                sub.addItem(del)
                row.submenu = sub
                menu.addItem(row)
            }
        }

        let addIgnore = NSMenuItem(title: s(.dictAddIgnore), action: #selector(addIgnoredPrompt), keyEquivalent: "")
        addIgnore.target = self
        menu.addItem(addIgnore)

        menu.addItem(.separator())

        let replHeader = NSMenuItem(title: s(.dictReplacements), action: nil, keyEquivalent: "")
        replHeader.isEnabled = false
        menu.addItem(replHeader)

        let pairs = settings.spellReplacements.sorted { $0.key < $1.key }
        if pairs.isEmpty {
            let empty = NSMenuItem(title: s(.dictEmpty), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for (from, to) in pairs.prefix(40) {
                let row = NSMenuItem(title: "\(from) → \(to)", action: nil, keyEquivalent: "")
                let sub = NSMenu()
                let del = NSMenuItem(title: s(.dictDelete), action: #selector(deleteReplacement(_:)), keyEquivalent: "")
                del.target = self
                del.representedObject = from
                sub.addItem(del)
                row.submenu = sub
                menu.addItem(row)
            }
        }

        let addRepl = NSMenuItem(title: s(.dictAddReplacement), action: #selector(addReplacementPrompt), keyEquivalent: "")
        addRepl.target = self
        menu.addItem(addRepl)

        return menu
    }

    private func buildSoundsSubmenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(soundRoleMenu(title: s(.soundToRussian), current: settings.soundPrefs.switchToRussian, role: "russian"))
        menu.addItem(soundRoleMenu(title: s(.soundToEnglish), current: settings.soundPrefs.switchToEnglish, role: "english"))
        menu.addItem(soundRoleMenu(title: s(.soundAuto), current: settings.soundPrefs.autoConvert, role: "auto"))
        menu.addItem(soundRoleMenu(title: s(.soundUndo), current: settings.soundPrefs.undo, role: "undo"))
        menu.addItem(soundRoleMenu(title: s(.soundSelection), current: settings.soundPrefs.selectionConvert, role: "selection"))
        menu.addItem(.separator())
        let reset = NSMenuItem(title: s(.soundReset), action: #selector(resetSounds), keyEquivalent: "")
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
        if status.hasPrefix("auto:") || status.hasPrefix("manual:") || status.hasPrefix("ignore:")
            || status.hasPrefix("teach:") || status.hasPrefix("selection:")
            || status.hasPrefix("pause:")
        {
            flashToken += 1
            let token = flashToken
            let mark: String
            if status.hasPrefix("ignore:") {
                mark = "·"
            } else if status.hasPrefix("teach:") {
                mark = "+"
            } else if status.hasPrefix("pause:on") {
                mark = "⏸"
            } else {
                mark = "✓"
            }
            lastTitle = mark
            item.button?.title = mark
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, self.flashToken == token else { return }
                self.lastTitle = ""
                self.refreshLayoutTitle()
            }
        } else {
            lastTitle = ""
            refreshLayoutTitle()
        }
        settings = orchestrator.currentSettings
        rebuildMenu()
    }

    @objc private func togglePause() {
        orchestrator.togglePause()
        settings = orchestrator.currentSettings
        lastTitle = ""
        refreshLayoutTitle()
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

    @objc private func toggleLaunchAtLogin() {
        let enabled = !settings.launchesOnStartup
        if LaunchAtLogin.setEnabled(enabled) {
            settings.launchesOnStartup = enabled
            persist()
        } else {
            settings.launchesOnStartup = LaunchAtLogin.isEnabled
            persist()
        }
    }

    @objc private func selectUILanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let language = UILanguage(rawValue: raw)
        else { return }
        settings.uiLanguage = language
        persist()
    }

    @objc private func selectChord(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        let parts = raw.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let chord = ModifierChord(rawValue: parts[1]) else { return }
        switch parts[0] {
        case "convert": settings.hotkeys.convert = chord
        case "teach": settings.hotkeys.teach = chord
        case "pause": settings.hotkeys.pause = chord
        default: return
        }
        persist()
    }

    @objc private func selectPauseDuration(_ sender: NSMenuItem) {
        guard let secs = sender.representedObject as? Double else { return }
        settings.hotkeys.pauseSeconds = secs
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

    @objc private func deleteIgnored(_ sender: NSMenuItem) {
        guard let word = sender.representedObject as? String else { return }
        orchestrator.removeIgnoredWord(word)
        settings = orchestrator.currentSettings
        rebuildMenu()
    }

    @objc private func deleteReplacement(_ sender: NSMenuItem) {
        guard let from = sender.representedObject as? String else { return }
        orchestrator.removeSpellReplacement(from: from)
        settings = orchestrator.currentSettings
        rebuildMenu()
    }

    @objc private func addIgnoredPrompt() {
        let alert = NSAlert()
        alert.messageText = s(.promptIgnoreTitle)
        alert.informativeText = s(.promptIgnoreBody)
        alert.alertStyle = .informational
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: s(.add))
        alert.addButton(withTitle: s(.cancel))
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        let word = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        orchestrator.addIgnoredWord(word)
        settings = orchestrator.currentSettings
        rebuildMenu()
    }

    @objc private func addReplacementPrompt() {
        let alert = NSAlert()
        alert.messageText = s(.promptReplaceTitle)
        alert.informativeText = "\(s(.promptReplaceFrom))\n\(s(.promptReplaceTo))"
        alert.alertStyle = .informational
        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 260, height: 56))
        stack.orientation = .vertical
        stack.spacing = 6
        let fromField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        fromField.placeholderString = s(.promptReplaceFrom)
        let toField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        toField.placeholderString = s(.promptReplaceTo)
        stack.addArrangedSubview(fromField)
        stack.addArrangedSubview(toField)
        alert.accessoryView = stack
        alert.addButton(withTitle: s(.add))
        alert.addButton(withTitle: s(.cancel))
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        let from = fromField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = toField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty, !to.isEmpty else { return }
        orchestrator.addSpellReplacement(from: from, to: to)
        settings = orchestrator.currentSettings
        rebuildMenu()
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
        alert.addButton(withTitle: s(.openLog))
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
