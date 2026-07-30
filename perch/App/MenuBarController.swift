import AppKit
import Logging

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let appState: AppState
    private let logger: Logger = {
        var logger = Logger(label: "com.tukuyomi032.perch.MenuBarController")
        logger.logLevel = .debug
        return logger
    }()

    init(appState: AppState) {
        self.appState = appState
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configure()
    }

    private func configure() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "bird", accessibilityDescription: "Perch")
        button.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Perch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        menu.items.first?.target = self
        statusItem.menu = menu
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if let action = appState.openSettingsAction {
            logger.debug("openSettings: invoking appState.openSettingsAction")
            action()
        } else {
            logger.debug("openSettings: appState.openSettingsAction is nil, falling back to sendAction directly")
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        Task { @MainActor [logger] in
            // Poll rather than a single fixed sleep — the Settings scene's first materialization
            // can take longer than a single short wait, especially on a cold SwiftUI compile.
            for attempt in 1...10 {
                try? await Task.sleep(for: .milliseconds(50))
                let windows = NSApp.windows
                let candidates = windows.map {
                    SettingsWindowSelector.Candidate(
                        canBecomeKey: $0.canBecomeKey,
                        isVisible: $0.isVisible,
                        isChrome: $0 is NookPanel
                    )
                }
                let keyableCount = candidates.filter { $0.canBecomeKey && $0.isVisible }.count
                logger.debug(
                    "openSettings: attempt \(attempt)/10, \(windows.count) window(s), \(keyableCount) keyable+visible"
                )
                if let index = SettingsWindowSelector.selectTarget(from: candidates) {
                    let target = windows[index]
                    target.makeKeyAndOrderFront(nil)
                    logger.debug("openSettings: made key \(target.title.isEmpty ? "(untitled)" : target.title)")
                    return
                }
            }
            logger.warning("openSettings: no keyable+visible window found after 10 attempts (500ms)")
        }
    }
}
