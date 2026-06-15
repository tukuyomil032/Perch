import AppKit
import Defaults

final class IslandWindow: NSWindow {
    private var allowsManagedFrameUpdate = false
    private var hasCompletedInitialSetup = false

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
        hasCompletedInitialSetup = true
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

    /// The only permitted path for changing the window frame.
    /// All callers must use this instead of setFrame(_:display:) directly.
    func applyManagedFrame(_ frame: NSRect, display: Bool = true, animate: Bool = false) {
        guard self.frame != frame else { return }
        allowsManagedFrameUpdate = true
        defer { allowsManagedFrameUpdate = false }
        if animate {
            animator().setFrame(frame, display: display)
        } else {
            super.setFrame(frame, display: display)
        }
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        guard hasCompletedInitialSetup else {
            super.setFrame(frameRect, display: flag)
            return
        }
        // Silently drop any frame request not from applyManagedFrame.
        // This breaks the SwiftUI NSHostingView → setFrame → layout → NSHostingView loop.
        guard allowsManagedFrameUpdate else { return }
        super.setFrame(frameRect, display: flag)
    }
}
