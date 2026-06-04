import AppKit

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem

    init() {
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
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let islandLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
            for win in NSApp.windows where win.level != islandLevel && win.isVisible && win.canBecomeKey {
                win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
                win.makeKeyAndOrderFront(nil)
            }
        }
    }
}
