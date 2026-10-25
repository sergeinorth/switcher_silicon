import AppKit
import Engine
import Platform

@MainActor
final class StatusBarController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let orchestrator: LayoutOrchestrator
    private let inputSources = InputSourceManager()
    private var settings: AppSettings
    private var flashToken = 0
    private var layoutPoll: Timer?
    private var lastTitle = ""

    init(orchestrator: LayoutOrchestrator) {
        self.orchestrator = orchestrator
        self.settings = orchestrator.currentSettings
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
        // Notifications are flaky ~1/5 — poll as source of truth.
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
        // Real readiness = event tap is up. AXIsProcessTrusted alone is unreliable for ad-hoc builds.
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

        let soundItem = NSMenuItem(
            title: settings.isSoundOn ? "Звуки: вкл" : "Звуки: выкл",
            action: #selector(toggleSound),
            keyEquivalent: ""
        )
        soundItem.target = self
        menu.addItem(soundItem)

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
        // Refresh diagnostic labels next open.
        rebuildMenu()
    }

    @objc private func toggleAuto() {
        settings.isAutocorrectionActive.toggle()
        orchestrator.reloadSettings(settings)
        settings = orchestrator.currentSettings
        rebuildMenu()
    }

    @objc private func toggleSound() {
        settings.isSoundOn.toggle()
        orchestrator.reloadSettings(settings)
        settings = orchestrator.currentSettings
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
            orchestrator.reloadSettings(settings)
            settings = orchestrator.currentSettings
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
