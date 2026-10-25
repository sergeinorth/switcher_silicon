import AppKit
import Engine
import Platform

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var orchestrator: LayoutOrchestrator!
    private var statusBar: StatusBarController!
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        AppLog.line("launch path=\(Bundle.main.bundlePath)")
        AppLog.line("perms \(AccessibilityPermission.diagnosticsLine)")

        let settings = SettingsStore.load()
        orchestrator = LayoutOrchestrator(settings: settings)
        statusBar = StatusBarController(orchestrator: orchestrator)

        // Always attempt tap — success is the real signal, not AXIsProcessTrusted.
        tryStartTap(reason: "launch")

        if !AccessibilityPermission.isReady || !(orchestrator?.isTapActive ?? false) {
            AccessibilityPermission.requestAll()
            showPermissionAlert()
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.tryStartTap(reason: "poll")
                }
            }
        }

        // Sync login item with saved preference (menu can change it later).
        _ = LaunchAtLogin.setEnabled(settings.launchesOnStartup)
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLog.line("terminate")
        orchestrator?.stop()
        permissionTimer?.invalidate()
    }

    private func tryStartTap(reason: String) {
        AppLog.line("tryStart(\(reason)) \(AccessibilityPermission.diagnosticsLine)")
        if orchestrator.isTapActive {
            if AccessibilityPermission.isReady {
                permissionTimer?.invalidate()
                permissionTimer = nil
            }
            return
        }
        let ok = orchestrator.start()
        AppLog.line("tap started=\(ok)")
        if ok {
            permissionTimer?.invalidate()
            permissionTimer = nil
            statusBar.refreshPermissionState()
        }
    }

    private func showPermissionAlert() {
        let lang = orchestrator.currentSettings.uiLanguage
        let alert = NSAlert()
        alert.messageText = L10n.t(.permTitle, lang)
        alert.informativeText = L10n.t(.permBody, lang)
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.t(.openInputMonitoring, lang).replacingOccurrences(of: "…", with: ""))
        alert.addButton(withTitle: L10n.t(.openAccessibility, lang).replacingOccurrences(of: "…", with: ""))
        alert.addButton(withTitle: L10n.t(.later, lang))
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            AccessibilityPermission.openInputMonitoringSettings()
        } else if response == .alertSecondButtonReturn {
            AccessibilityPermission.openAccessibilitySettings()
        }
    }

}
