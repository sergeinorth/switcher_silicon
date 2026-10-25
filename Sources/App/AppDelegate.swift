import AppKit
import Engine
import Platform
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var orchestrator: LayoutOrchestrator!
    private var statusBar: StatusBarController!
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        AppLog.line("launch path=\(Bundle.main.bundlePath)")
        AppLog.line("AX trusted=\(AccessibilityPermission.isTrusted)")

        let settings = SettingsStore.load()
        orchestrator = LayoutOrchestrator(settings: settings)
        statusBar = StatusBarController(orchestrator: orchestrator)

        if AccessibilityPermission.isTrusted {
            let ok = orchestrator.start()
            AppLog.line("tap started=\(ok)")
        } else {
            AppLog.line("AX missing — prompting")
            AccessibilityPermission.promptIfNeeded()
            showPermissionAlert()
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.tryStartWhenTrusted()
                }
            }
        }

        // Login items are flaky for ad-hoc apps — keep off unless it already works.
        if settings.launchesOnStartup {
            configureLaunchAtLogin(true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLog.line("terminate")
        orchestrator?.stop()
        permissionTimer?.invalidate()
    }

    private func tryStartWhenTrusted() {
        let trusted = AccessibilityPermission.isTrusted
        AppLog.line("poll AX trusted=\(trusted)")
        guard trusted else { return }
        permissionTimer?.invalidate()
        permissionTimer = nil
        let ok = orchestrator.start()
        AppLog.line("tap started after AX=\(ok)")
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Нужен доступ к Универсальному доступу"
        alert.informativeText = """
        Switcher Silicon должен быть в списке и включён.

        1. Открой Универсальный доступ
        2. Выключи SwitcherSilicon и включи снова
        3. Если пунктов несколько — оставь только /Applications/SwitcherSilicon.app

        Caramba искать не нужно, если её нет в списке.
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
            AppLog.line("login item error: \(error)")
        }
    }
}
