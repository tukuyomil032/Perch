import Foundation
import ServiceManagement
import Logging

enum LoginItemManager {
    private static let logger = Logger(label: "com.tukuyomi032.perch.LoginItemManager")

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                logger.info("Login item registered")
            } else {
                try SMAppService.mainApp.unregister()
                logger.info("Login item unregistered")
            }
        } catch {
            logger.error("Failed to \(enabled ? "register" : "unregister") login item: \(error)")
        }
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
