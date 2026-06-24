import AppKit
import Defaults
import QuartzCore

struct IslandWindowFrameTransition {
    let duration: TimeInterval
    let timingFunction: CAMediaTimingFunction

    static let open = IslandWindowFrameTransition(
        duration: DesignSystem.Motion.shellDuration,
        timingFunction: DesignSystem.Motion.appKitOpenTiming
    )

    static let close = IslandWindowFrameTransition(
        duration: DesignSystem.Motion.closeDuration,
        timingFunction: DesignSystem.Motion.appKitCloseTiming
    )
}

@MainActor
final class IslandWindow: NSWindow {
    private var managedFrameUpdateDepth = 0
    private var hasCompletedInitialSetup = false

    /// True while a managed frame animation (open or close transition) is in flight.
    /// Used by IslandWindowController to detect the close-during-open race condition.
    var isAnimatingFrame: Bool { managedFrameUpdateDepth > 0 }

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
    func applyManagedFrame(_ frame: NSRect, display: Bool = true, transition: IslandWindowFrameTransition? = nil) {
        guard self.frame != frame else { return }
        managedFrameUpdateDepth += 1
        if let transition {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = transition.duration
                context.timingFunction = transition.timingFunction
                self.animator().setFrame(frame, display: display)
            } completionHandler: { [weak self] in
                self?.managedFrameUpdateDepth -= 1
            }
        } else {
            defer { managedFrameUpdateDepth -= 1 }
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
        guard managedFrameUpdateDepth > 0 else { return }
        super.setFrame(frameRect, display: flag)
    }
}
