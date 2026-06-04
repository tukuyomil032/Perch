import AppKit

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let appState: AppState

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
            action()
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            for win in NSApp.windows where win.canBecomeKey && win.isVisible {
                win.makeKeyAndOrderFront(nil)
            }
        }
    }
}
