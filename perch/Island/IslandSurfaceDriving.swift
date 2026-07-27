import AppKit
import Combine

/// The slice of the vendored notch surface that `NookBridge` actually drives.
///
/// Deliberately free of any `Nook*` type: the whole point is that the bridge's logic —
/// auto-collapse timing, window chrome re-application — can be exercised against a fake
/// in `perchTests`, and that the vendoring dependency stays pinned to one conformance
/// (`Nook: IslandSurfaceDriving`, below) instead of spreading through Perch.
///
/// The member names match `Nook`'s existing API exactly, so the conformance is
/// declaration-only. That is intentional: a protocol that renamed things would need an
/// adapter layer, and an adapter is one more place for the two vocabularies to drift.
///
/// `NSWindow` and Combine appear here and that is fine — they are system frameworks, not
/// vendored code. What must not leak is `NookState` / `NookPresentation` / `NookStyle`,
/// because those are what a re-sync with upstream can change out from under us.
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

    /// Fires on every transition *into* the expanded surface, whatever caused it.
    var onExpand: (@MainActor () -> Void)? { get set }

    /// Fires on every transition *into* the compact pill.
    var onCompact: (@MainActor () -> Void)? { get set }

    /// Awaits until the expansion has settled. Passing `nil` lets the surface resolve
    /// the target screen itself.
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
}
