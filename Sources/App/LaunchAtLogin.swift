import Foundation
import Platform
import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            AppLog.line("launch at login => \(enabled)")
            return true
        } catch {
            AppLog.line("launch at login error: \(error)")
            return false
        }
    }
}
