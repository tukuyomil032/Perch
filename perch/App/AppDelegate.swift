import AppKit
import Logging
import ScreenCaptureKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var islandHost: IslandHost?
    private var menuBarController: MenuBarController?
    let appState = AppState()
    private let logger = Logger(label: "com.tukuyomi032.perch.AppDelegate")

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Perch launching")
        NSApp.setActivationPolicy(.accessory)

        // Before anything reads a preference: carries pre-A5 installs over to the renamed
        // island keys and drops the retired ones.
        PreferencesMigration.runAll()

        menuBarController = MenuBarController(appState: appState)

        // Widget registration must precede the island: the expanded content renders the
        // active preset's widgets by id, and an unregistered id draws nothing.
        appState.widgetRegistry.register(NowPlayingWidget())
        appState.widgetRegistry.register(AIUsageWidget())

        islandHost = IslandHost(appState: appState)

        appState.aiUsageStore.registerProvider(ClaudeProvider())
        appState.aiUsageStore.registerProvider(CodexProvider())
        appState.aiUsageStore.registerProvider(OpenAIProvider())
        appState.aiUsageStore.registerProvider(OpenRouterProvider())
        Task {
            await appState.aiUsageStore.refresh()
            await appState.aiUsageStore.startAutoRefresh()
        }

        // Request ScreenCapture permission on first launch
        Task {
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            } catch {
                logger.error("ScreenCapture permission request failed: \(String(describing: error))")
            }
        }

        logger.info("Perch launch complete")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
