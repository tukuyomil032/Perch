import AppKit
import Logging

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: IslandWindowController?
    private var menuBarController: MenuBarController?
    private var mouseMonitor: MouseEventMonitor?
    private let appState = AppState()
    private let logger = Logger(label: "com.tukuyomi032.perch.AppDelegate")

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Perch launching")
        NSApp.setActivationPolicy(.accessory)

        menuBarController = MenuBarController(appState: appState)
        windowController = IslandWindowController(appState: appState)
        mouseMonitor = MouseEventMonitor(
            appState: appState,
            windowController: windowController!
        )
        mouseMonitor?.startMonitoring()

        appState.aiUsageStore.registerProvider(ClaudeProvider())
        Task {
            await appState.aiUsageStore.refresh()
            await appState.aiUsageStore.startAutoRefresh()
        }

        logger.info("Perch launch complete")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
