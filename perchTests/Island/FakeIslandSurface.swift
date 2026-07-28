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
/// 4. `applyChromeStyle` / `applySyntheticNotchWidth` rebuild the window only when the
///    value actually changes, matching the `didSet` guards on `Nook.presentation` and
///    `Nook.syntheticNotchWidth`.
@MainActor
final class FakeIslandSurface: IslandSurfaceDriving {
    enum State: Equatable {
        case hidden
        case compact
        case expanded
    }

    private let hoverSubject = CurrentValueSubject<Bool, Never>(false)

    var isHovering: Bool { hoverSubject.value }
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
        guard style != currentChromeStyle, state != .hidden else { return }
        currentChromeStyle = style
        simulateWindowRebuild()
    }

    /// Same early-return shape as ``applyChromeStyle(_:)`` — `Nook.syntheticNotchWidth`
    /// carries the identical `didSet` guard.
    func applySyntheticNotchWidth(_ width: CGFloat) {
        appliedSyntheticNotchWidths.append(width)
        guard width != currentSyntheticNotchWidth, state != .hidden else { return }
        currentSyntheticNotchWidth = width
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

    /// Plays back a hover transition the way the real surface publishes it.
    func setHovering(_ hovering: Bool) {
        hoverSubject.send(hovering)
    }

    /// Plays back an explicit `hide()`: the real surface publishes the hidden state and
    /// clears hover inside the same animation block, in that order.
    func simulateHide() async {
        await transition(to: .hidden)
        hoverSubject.send(false)
    }

    /// Plays back the surface building a fresh panel — on a transition out of hidden, a
    /// presentation change, or a display change. The new panel carries `NookPanel`'s own
    /// defaults, which is precisely why the bridge has to re-apply chrome.
    func simulateWindowRebuild() {
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
