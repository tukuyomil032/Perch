import AppKit
import Testing

@testable import perch

/// Covers the part of `IslandHost` that does not need a screen.
///
/// `IslandHost` itself is not constructible under test: its `init` builds a real
/// `Nook`, registers `NSWorkspace` and `Defaults` observers against the shared suite, and
/// kicks off a `Task` that mounts a panel. What *is* testable is the per-window setup it
/// hands the bridge, which needs nothing but an `NSWindow` — so that is what is extracted
/// and pinned here. The observer wiring and the `restoreSurfaceIfLost` predicate are left
/// alone deliberately: the first is AppKit/Defaults registration with no logic of its own,
/// and the second is a two-term boolean whose test could only restate it.
@MainActor
struct IslandHostTests {
    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 40),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 40))
        return window
    }

    @Test("attaching to a window puts the recognizer on its content view")
    func attachInstallsTheRecognizer() {
        let window = makeWindow()
        let recognizer = NSClickGestureRecognizer()

        IslandHost.attach(recognizer, to: window)

        #expect(window.contentView?.gestureRecognizers.count == 1)
        #expect(recognizer.view === window.contentView)
    }

    /// The surface rebuilds its panel on nearly every path, so the configurator runs
    /// constantly against the *same* window. Stacking a second copy would fire the
    /// expand/collapse toggle twice per click — a bug with no error anywhere.
    @Test("re-attaching to the same window does not stack a second recognizer")
    func attachIsIdempotent() {
        let window = makeWindow()
        let recognizer = NSClickGestureRecognizer()

        IslandHost.attach(recognizer, to: window)
        IslandHost.attach(recognizer, to: window)
        IslandHost.attach(recognizer, to: window)

        #expect(window.contentView?.gestureRecognizers.count == 1)
    }

    /// The other half: when the surface hands back a *new* panel, the recognizer has to
    /// move. Left on the old one, the island would be silently unclickable.
    @Test("attaching to a new window moves the recognizer off the old one")
    func attachMovesToTheNewWindow() {
        let first = makeWindow()
        let second = makeWindow()
        let recognizer = NSClickGestureRecognizer()

        IslandHost.attach(recognizer, to: first)
        IslandHost.attach(recognizer, to: second)

        #expect(first.contentView?.gestureRecognizers.isEmpty == true)
        #expect(second.contentView?.gestureRecognizers.count == 1)
        #expect(recognizer.view === second.contentView)
    }

    /// A window with no content view is not a state to crash on — the surface tears its
    /// panel down and rebuilds it, and the configurator can land mid-rebuild.
    @Test("a window with no content view is skipped rather than crashing")
    func attachToContentlessWindowIsInert() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 40),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        window.contentView = nil
        let recognizer = NSClickGestureRecognizer()

        IslandHost.attach(recognizer, to: window)

        #expect(recognizer.view == nil)
    }
}
