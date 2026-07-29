import AppKit
import Combine

/// The slice of the vendored notch surface that `NookBridge` actually drives.
///
/// Deliberately free of any `Nook*` type: the whole point is that the bridge's logic —
/// auto-collapse timing, window chrome re-application — can be exercised against a fake
/// in `perchTests`, and that the vendoring dependency stays pinned to one conformance
/// (`Nook: IslandSurfaceDriving`, below) instead of spreading through Perch.
///
/// The member names match `Nook`'s existing API wherever they can, so most of the
/// conformance is declaration-only. The exceptions are the three `apply…` methods: they
/// take Perch's own vocabulary (`IslandChromeStyle`, a width, a boolean) and the
/// conformance translates each into the Kit type it maps onto — which is what keeps
/// `NookPresentation` and `NookBackdrop` confined to this one file.
///
/// `NSScreen`, `NSWindow` and Combine appear here and that is fine — they are system
/// frameworks, not vendored code. What must not leak is `NookState` / `NookPresentation` /
/// `NookStyle` / `NookBackdrop`, because those are what a re-sync with upstream can change
/// out from under us.
@MainActor
protocol IslandSurfaceDriving: AnyObject {
    /// `true` while the cursor is over the surface's *visible* shape (not its window
    /// rect — the vendored surface hit-tests against the notch path).
    var isHovering: Bool { get }

    /// Hover transitions, for hosts that want to drive their own timing off them.
    var isHoveringPublisher: AnyPublisher<Bool, Never> { get }

    /// When `true`, the surface does not auto-compact the moment the cursor leaves.
    /// Perch sets this so `NookBridge` can honour the user's auto-collapse delay.
    var staysExpandedOnHoverExit: Bool { get set }

    /// Resolves the display the chrome should occupy when a caller passes no screen.
    /// This is how a persisted display preference reaches the surface: without it the
    /// surface falls back to the system main screen and the preference is inert.
    var screenProvider: (@MainActor () -> NSScreen?)? { get set }

    /// When `true`, converting between compact and expanded goes straight across instead
    /// of dipping through the hidden state on the way. Perch turns this on: the island
    /// has always animated its frame directly, and a dip through hidden both looks wrong
    /// and makes the surface report a hide that never conceptually happened.
    var skipsIntermediateHides: Bool { get set }

    /// Fires on every transition *into* the expanded surface, whatever caused it.
    var onExpand: (@MainActor () -> Void)? { get set }

    /// Fires on every transition *into* the compact pill.
    var onCompact: (@MainActor () -> Void)? { get set }

    /// Fires on every transition *into* the hidden state.
    ///
    /// Not optional to handle: hiding is not only an explicit `hide()`. A surface built
    /// with no compact content turns `compact()` into a full hide, so `onHide` is the
    /// only collapse signal such a surface ever emits — and the hidden transition also
    /// publishes `isHovering = false`, which a host tracking expansion from
    /// `onExpand`/`onCompact` alone would misread as "the cursor left an expanded
    /// surface".
    var onHide: (@MainActor () -> Void)? { get set }

    /// Awaits until the expansion has settled. Passing `nil` lets the surface resolve
    /// the target screen itself (see ``screenProvider``).
    func expand(on screen: NSScreen?) async

    /// Awaits until the collapse has settled. See ``expand(on:)`` for `screen`.
    func compact(on screen: NSScreen?) async

    /// Switches the chrome between the pseudo-notch and floating looks. Takes Perch's own
    /// `IslandChromeStyle`, not the vendored presentation enum, so the mapping onto the Kit
    /// vocabulary lives in exactly one place (the `Nook` conformance below).
    ///
    /// Callable at any time, including while the surface is on screen: the vendored
    /// surface rebuilds its visible window when its presentation changes, so a style
    /// switch from Settings takes effect immediately rather than on next launch.
    func applyChromeStyle(_ style: IslandChromeStyle)

    /// Sets the width of the notch shape drawn on displays with no physical notch — the
    /// knob vendoring existed to obtain. Like ``applyChromeStyle(_:)`` it rebuilds a
    /// visible window in place.
    func applySyntheticNotchWidth(_ width: CGFloat)

    /// `true` while the surface has a window on screen. Hosts use it to notice that the
    /// island has vanished — the surface can fail to build one (no screen resolves) and
    /// never retries on its own.
    var hasLiveWindow: Bool { get }

    /// Rebuilds the visible window on the currently-resolved screen, *unconditionally*.
    ///
    /// Distinct from ``applyChromeStyle(_:)`` and ``applySyntheticNotchWidth(_:)``, which
    /// only rebuild when the value they set actually changes. That difference is the whole
    /// reason this exists: moving the island to a different display changes neither the
    /// chrome style nor the notch width, so re-applying one of those to force a move is a
    /// silent no-op — the surface stays exactly where it was.
    ///
    /// No-op while hidden: there is no visible window to rebuild.
    func relocate()

    /// Paints the chrome's backdrop for the current transparency setting. The decision
    /// (which material, how dark) stays in `NookBridge.makeBackdrop(reduceTransparency:)`;
    /// only the assignment lives in the conformance, so the Kit type never reaches a
    /// call site.
    func applyBackdrop(reduceTransparency: Bool)

    /// Applies window-level tweaks to the currently mounted window. Returns `false`
    /// when there is no live window — the surface tears its window down and rebuilds it
    /// across transitions, which is exactly why chrome has to be re-applied.
    @discardableResult
    func configureWindow(_ apply: (NSWindow) -> Void) -> Bool
}

extension Nook: IslandSurfaceDriving {
    var isHoveringPublisher: AnyPublisher<Bool, Never> {
        $isHovering.eraseToAnyPublisher()
    }

    /// The single point where a Perch chrome style becomes a vendored `NookPresentation`.
    /// Assigning `presentation` is what triggers the surface's in-place window rebuild.
    func applyChromeStyle(_ style: IslandChromeStyle) {
        presentation = style.nookPresentation
    }

    func applySyntheticNotchWidth(_ width: CGFloat) {
        syntheticNotchWidth = width
    }

    /// `rebuildVisibleWindow(on:)` is `internal` to the vendored module, which this
    /// extension is inside — so the seam needs no change to `Vendor` source. It re-resolves
    /// the screen through `resolvedScreen`, which is what makes this a *move* rather than
    /// just a rebuild in place.
    func relocate() {
        guard state != .hidden, let screen = resolvedScreen else { return }
        rebuildVisibleWindow(on: screen)
    }

    var skipsIntermediateHides: Bool {
        get { transitionConfiguration.skipIntermediateHides }
        set { transitionConfiguration.skipIntermediateHides = newValue }
    }

    /// The single point where a Perch backdrop decision becomes a vendored `NookBackdrop`.
    func applyBackdrop(reduceTransparency: Bool) {
        backdrop = NookBridge.makeBackdrop(reduceTransparency: reduceTransparency)
    }
}
