import AppKit
import Defaults

final class IslandWindow: NSWindow {
    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        configure()
    }

    private func configure() {
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        var behavior: NSWindow.CollectionBehavior = [.fullScreenAuxiliary, .stationary, .ignoresCycle]
        if Defaults[.showInAllSpaces] {
            behavior.insert(.canJoinAllSpaces)
        }
        collectionBehavior = behavior
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        tabbingMode = .disallowed
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Prevent SwiftUI's updateAnimatedWindowSize from recursively calling setFrame
    // during a layout pass, which causes an infinite constraint loop and crash.
    private var isUpdatingFrame = false

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        guard !isUpdatingFrame else { return }
        isUpdatingFrame = true
        defer { isUpdatingFrame = false }
        super.setFrame(frameRect, display: flag)
    }
}
