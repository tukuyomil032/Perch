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
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
