import AppKit
import Combine

@testable import perch

/// In-memory stand-in for the vendored notch surface.
///
/// Exists so `NookBridge` — and, from A5 on, `AppState`'s transition tests — can be
/// driven without mounting a real `NSPanel`, and so tests can play back hover, hide and
/// window-rebuild events in an order a real surface would only produce with a live cursor
/// and a display being unplugged.
///
/// It mirrors three behaviours of the real surface that the bridge's correctness depends
/// on, because a fake more forgiving than the real thing is a test hole:
/// 1. lifecycle callbacks fire only on an actual state *change* (the real surface returns
///    early when asked to expand an already-expanded surface on the same screen);
/// 2. `compact()` can settle as *hidden* rather than compact (``compactCollapsesToHide``),
///    which is what the real surface does when it has no compact content;
/// 3. building a window resets its chrome to the vendored panel's defaults
///    (``simulateWindowRebuild()``), so "the bridge re-applied chrome" is observable as a
///    property value rather than only as a call count;
/// 4. `applyChromeStyle` / `applySyntheticNotchWidth` *record* the value unconditionally
///    but rebuild the window only when it actually changes, matching the `didSet` guards on
///    the stored `Nook.presentation` and `Nook.syntheticNotchWidth` — including while
///    hidden, where the assignment still lands even though nothing is rebuilt.
@MainActor
final class FakeIslandSurface: IslandSurfaceDriving {
    enum State: Equatable {
        case hidden
        case compact
        case expanded
    }

    private let hoverSubject = CurrentValueSubject<Bool, Never>(false)

    /// Held separately from ``hoverSubject`` so ``suppressesHoverEvents`` can drive the two
    /// apart. On the real surface they are also distinct: `isHovering` is a stored property
    /// that SwiftUI's `.onHover` writes, and `.onHover` makes no promise to fire for a
    /// cursor that was already resting over the region when the hosting view appeared
    /// beneath it — so "hovering, but no event was ever delivered" is a real state.
    private var hoverState = false

    /// When set, ``setHovering(_:)`` updates the surface's live hover state without
    /// publishing it, reproducing the dropped `.onHover` above.
    var suppressesHoverEvents = false

    var isHovering: Bool { hoverState }
    var isHoveringPublisher: AnyPublisher<Bool, Never> { hoverSubject.eraseToAnyPublisher() }

    var staysExpandedOnHoverExit = false
    var skipsIntermediateHides = false

    /// Reproduces the vendored default (`skipIntermediateHides == false`), where
    /// converting between compact and expanded dips through `.hidden` and fires `onHide`
    /// on the way. Kept independent of ``skipsIntermediateHides`` so a test can force the
    /// dip and prove the bridge filters the report even if the setting is ever lost.
    var usesIntermediateHides = false
    var screenProvider: (@MainActor () -> NSScreen?)?
    var onExpand: (@MainActor () -> Void)?
    var onCompact: (@MainActor () -> Void)?
    var onHide: (@MainActor () -> Void)?

    private(set) var state: State = .hidden
    private(set) var expandCallCount = 0
    private(set) var compactCallCount = 0
    private(set) var configureWindowCallCount = 0
    private(set) var relocateCallCount = 0

    /// How many times a fresh panel was built. Exists because "the bridge re-applied chrome"
    /// and "the surface rebuilt the window" are otherwise indistinguishable from the window's
    /// properties alone: `applyWindowChrome()` runs on every path and restores the same
    /// values a rebuild reset, so a chrome assertion passes whether or not the rebuild
    /// happened. Tests that mean to pin *rebuild* behaviour must read this instead.
    private(set) var windowRebuildCount = 0

    /// Tracks the values the real surface compares against in its `didSet` guards.
    private var currentChromeStyle: IslandChromeStyle?
    private var currentSyntheticNotchWidth: CGFloat?

    /// Every chrome style handed to the surface, in order, so a test can assert on live
    /// switching rather than just the final value.
    private(set) var appliedChromeStyles: [IslandChromeStyle] = []

    /// Every `applyBackdrop(reduceTransparency:)` argument, in order.
    private(set) var appliedBackdropReduceTransparency: [Bool] = []

    private(set) var appliedSyntheticNotchWidths: [CGFloat] = []

    /// Reproduces a surface built without compact content: `compact()` collapses all the
    /// way to hidden and reports `onHide`, never `onCompact`.
    var compactCollapsesToHide = false

    /// `false` reproduces a hidden surface, where there is no window to configure.
    var hasLiveWindow = true

    /// The window `configureWindow` hands out, so a test can assert on what was applied.
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 100, height: 40),
        styleMask: [.borderless],
        backing: .buffered,
        defer: true
    )

    init() {
        resetWindowToVendoredDefaults()
    }

    func expand(on screen: NSScreen?) async {
        expandCallCount += 1
        await transition(to: .expanded)
    }

    func compact(on screen: NSScreen?) async {
        compactCallCount += 1
        await transition(to: compactCollapsesToHide ? .hidden : .compact)
    }

    /// Mirrors `Nook.presentation`'s `didSet`, which rebuilds the visible window only when
    /// the value actually *changes* and the surface is not hidden
    /// (`guard presentation != oldValue, state != .hidden`). Re-applying the current style
    /// is a no-op on the real surface, so it has to be one here too — a fake that rebuilt
    /// unconditionally would let a host "relocate the island by re-applying its style" pass
    /// in tests while doing nothing at all in production.
    func applyChromeStyle(_ style: IslandChromeStyle) {
        appliedChromeStyles.append(style)
        // The vendored property is *stored*: the assignment always lands, and the `didSet`
        // guard only skips the rebuild. Updating the tracked value unconditionally is what
        // keeps the hidden case honest — `IslandHost.applyInitialConfiguration()` applies a
        // style before the surface is ever shown, and a fake that dropped that value would
        // rebuild on the next identical application while the real surface would not.
        let changed = style != currentChromeStyle
        currentChromeStyle = style
        guard changed, state != .hidden else { return }
        simulateWindowRebuild()
    }

    /// Same early-return shape as ``applyChromeStyle(_:)`` — `Nook.syntheticNotchWidth`
    /// carries the identical `didSet` guard, and is likewise a stored property.
    func applySyntheticNotchWidth(_ width: CGFloat) {
        appliedSyntheticNotchWidths.append(width)
        let changed = width != currentSyntheticNotchWidth
        currentSyntheticNotchWidth = width
        guard changed, state != .hidden else { return }
        simulateWindowRebuild()
    }

    /// Unconditionally rebuilds the window on the resolved screen, the way
    /// `Nook.rebuildVisibleWindow(on:)` does. No-op while hidden: there is no visible
    /// window to rebuild.
    func relocate() {
        guard state != .hidden else { return }
        relocateCallCount += 1
        simulateWindowRebuild()
    }

    func applyBackdrop(reduceTransparency: Bool) {
        appliedBackdropReduceTransparency.append(reduceTransparency)
    }

    @discardableResult
    func configureWindow(_ apply: (NSWindow) -> Void) -> Bool {
        guard hasLiveWindow else { return false }
        configureWindowCallCount += 1
        apply(window)
        return true
    }

    // MARK: - Test drivers

    /// Plays back a hover transition the way the real surface publishes it — or, with
    /// ``suppressesHoverEvents`` set, the way it fails to.
    func setHovering(_ hovering: Bool) {
        hoverState = hovering
        guard !suppressesHoverEvents else { return }
        hoverSubject.send(hovering)
    }

    /// Plays back an explicit `hide()`: the real surface publishes the hidden state and
    /// clears hover inside the same animation block, in that order.
    func simulateHide() async {
        await transition(to: .hidden)
        hoverState = false
        hoverSubject.send(false)
    }

    /// Plays back the surface building a fresh panel — on a transition out of hidden, a
    /// presentation change, or a display change. The new panel carries `NookPanel`'s own
    /// defaults, which is precisely why the bridge has to re-apply chrome.
    func simulateWindowRebuild() {
        windowRebuildCount += 1
        resetWindowToVendoredDefaults()
    }

    private func transition(to newState: State) async {
        // The real surface returns early rather than re-firing a lifecycle hook for a
        // transition that would not change anything.
        guard newState != state else { return }

        // Evaluated before the dip below: the real surface's conversion path does not
        // build a window (`needsNewWindow == false`), so passing through `.hidden`
        // mid-conversion must not look like a rebuild here either.
        let wasHidden = state == .hidden

        // The intermediate hide the real surface performs mid-conversion.
        if usesIntermediateHides, state != .hidden, newState != .hidden {
            state = .hidden
            onHide?()
            // The real surface sleeps for `intermediateHideDuration` here (Nook.swift:653),
            // releasing the main actor. Anything the host queued in response to `onHide`
            // gets to run before the conversion completes — which a synchronous fake would
            // hide entirely.
            await Task.yield()
            await Task.yield()
        }

        state = newState
        if wasHidden { simulateWindowRebuild() }

        switch newState {
        case .expanded: onExpand?()
        case .compact: onCompact?()
        case .hidden: onHide?()
        }
    }

    /// Mirrors `NookPanel.init`: `.canJoinAllSpaces` unconditionally, and no opinion at
    /// all about `isOpaque` / `isReleasedWhenClosed`.
    private func resetWindowToVendoredDefaults() {
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
        window.isOpaque = true
        window.isReleasedWhenClosed = true
    }
}
