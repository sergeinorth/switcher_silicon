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
        orchestrator.onStatusChange = { [weak self] status in
            Task { @MainActor in
                self?.reflectStatus(status)
            }
        }
    }

    private func layoutTitle() -> String {
        inputSources.isCurrentRussian ? "РУ" : "EN"
    }

    private func refreshLayoutTitle() {
        item.button?.title = layoutTitle()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let layoutItem = NSMenuItem(
            title: "Раскладка: \(layoutTitle())",
            action: nil,
            keyEquivalent: ""
        )
        layoutItem.isEnabled = false
        menu.addItem(layoutItem)
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

        let accessItem = NSMenuItem(title: "Открыть доступность…", action: #selector(openAccessibility), keyEquivalent: "")
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
            item.button?.title = "✓"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, self.flashToken == token else { return }
                self.refreshLayoutTitle()
            }
        } else if status == "no-tap" {
            item.button?.title = "!"
        } else {
            refreshLayoutTitle()
        }
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
        AccessibilityPermission.openSettings()
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
