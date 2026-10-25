import AppKit
import Engine
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var orchestrator: LayoutOrchestrator!
    private var statusBar: StatusBarController!
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let settings = SettingsStore.load()
        orchestrator = LayoutOrchestrator(settings: settings)
        statusBar = StatusBarController(orchestrator: orchestrator)

        if !AccessibilityPermission.isTrusted {
            AccessibilityPermission.promptIfNeeded()
            showPermissionAlert()
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.tryStartWhenTrusted()
                }
            }
        } else {
            _ = orchestrator.start()
        }

        configureLaunchAtLogin(settings.launchesOnStartup)
    }

    func applicationWillTerminate(_ notification: Notification) {
        orchestrator?.stop()
        permissionTimer?.invalidate()
    }

    private func tryStartWhenTrusted() {
        guard AccessibilityPermission.isTrusted else { return }
        permissionTimer?.invalidate()
        permissionTimer = nil
        _ = orchestrator.start()
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Нужен доступ к Универсальному доступу"
        alert.informativeText = """
        Switcher Silicon перехватывает клавиатуру, чтобы чинить слова, набранные в неверной раскладке.

        Системные настройки → Конфиденциальность и безопасность → Универсальный доступ → включи SwitcherSilicon.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Открыть настройки")
        alert.addButton(withTitle: "Позже")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            AccessibilityPermission.openSettings()
        }
    }

    private func configureLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Login item may fail for unpackaged debug binaries — ignore in MVP.
        }
    }
}
