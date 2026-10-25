import AppKit
import Engine
import Platform

@MainActor
final class StatusBarController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let orchestrator: LayoutOrchestrator
    private var settings: AppSettings

    init(orchestrator: LayoutOrchestrator) {
        self.orchestrator = orchestrator
        self.settings = orchestrator.currentSettings
        if let button = item.button {
            button.title = "РУ"
            button.toolTip = "Switcher Silicon"
        }
        rebuildMenu()
        orchestrator.onStatusChange = { [weak self] status in
            Task { @MainActor in
                self?.reflectStatus(status)
            }
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()

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
        if let button = item.button {
            if status.hasPrefix("auto:") || status.hasPrefix("manual:") {
                button.title = "✓"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    self?.item.button?.title = "РУ"
                }
            } else if status == "no-tap" {
                button.title = "!"
            } else {
                button.title = "РУ"
            }
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
