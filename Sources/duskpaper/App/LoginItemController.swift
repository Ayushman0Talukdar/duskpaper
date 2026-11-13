import AppKit
import ServiceManagement

/// Wraps `SMAppService` so the app can offer "launch at login" without
/// scattering availability checks across the UI.
enum LoginItemController {
    static var isSupported: Bool { SMAppService.mainApp.status != .notRegistered || FileManager.default.isWritableFile(atPath: "/Library/LaunchAgents") }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                    Log.info("Login item registered")
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                    Log.info("Login item unregistered")
                }
            }
        } catch {
            Log.error("Login item: could not toggle the login item — \(error.localizedDescription)")
        }
    }
}
