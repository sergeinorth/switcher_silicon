import ApplicationServices
import AppKit
import CoreGraphics

enum AccessibilityPermission {
    /// Legacy Accessibility trust (Universal Access list).
    static var isAXTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Modern Input Monitoring / post-event access used by CGEventTap.
    static var canListenEvents: Bool {
        CGPreflightListenEventAccess()
    }

    static var canPostEvents: Bool {
        CGPreflightPostEventAccess()
    }

    /// Enough to run our tap + synth.
    static var isReady: Bool {
        // Prefer modern preflight; AX alone is not enough on recent macOS,
        // and AXIsProcessTrusted often stays false for ad-hoc apps even when toggled on.
        canListenEvents && canPostEvents
    }

    static func requestAll() {
        // Shows "Input Monitoring" prompt when needed.
        _ = CGRequestListenEventAccess()
        _ = CGRequestPostEventAccess()

        // Also nudge classic Accessibility prompt.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
        ]
        for s in urls {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }

    static func openInputMonitoringSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent",
        ]
        for s in urls {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }

    static func openSettings() {
        openInputMonitoringSettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            openAccessibilitySettings()
        }
    }

    static var diagnosticsLine: String {
        "AX=\(isAXTrusted) listen=\(canListenEvents) post=\(canPostEvents)"
    }
}
