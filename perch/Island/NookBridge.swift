import AppKit
import Combine
import Defaults
import Logging

private let logger = Logger(label: "com.tukuyomi032.perch.NookBridge")

/// Owns the vendored notch surface and everything Perch has to do *around* it: honour
/// the auto-collapse delay, and re-apply window chrome the surface does not know about.
///
/// This is what `IslandWindowController` shrinks to. The controller computed frames,
/// tracked transition direction, animated the window and mirrored sizes back into
/// `AppState`; the vendored surface owns all of that now, so what is left is policy the
/// surface has no opinion about.
///
/// **Dependency direction.** The bridge does not know `AppState` exists — it publishes
/// `onSurfaceExpanded` / `onSurfaceCompacted` closures instead. Two reasons: the surface,
/// not Perch, is about to become the source of truth for expansion state (A5 turns
/// `AppState.presentation` into a one-way derivation of exactly these callbacks), and a
/// bridge that reached into `AppState` would make it impossible to test either side
/// without dragging the other in. The bridge also deliberately holds no reference to
/// `AppState.transitionGeneration`, the 110ms/500ms timers, or the `.expanding` /
/// `.collapsing` presentation cases — all four are slated for deletion in A5 because the
/// surface already provides the equivalent.
@MainActor
final class NookBridge {
    /// Existential rather than a generic parameter: the concrete `Nook` is generic over
    /// three view types, so a generic bridge would leak those into every call site and
    /// into `AppState`. The bridge calls at most a handful of methods per transition, so
    /// the witness-table indirection is not worth a type-parameter cascade.
    private let surface: any IslandSurfaceDriving

    /// Read at *scheduling* time, not at init, so a preference change takes effect on the
    /// next hover exit rather than on the next launch. Injectable for tests, which must
    /// not depend on (or mutate) the shared `Defaults` suite.
    private let collapseDelay: @MainActor () -> Duration

    /// Called when the surface has settled into its expanded / compact state, from any
    /// cause — a `NookBridge.expand()`, a hover, a file drag.
    var onSurfaceExpanded: (@MainActor () -> Void)?
    var onSurfaceCompacted: (@MainActor () -> Void)?

    private var isSurfaceExpanded = false
    private var collapseTask: Task<Void, Never>?
    private var hoverSubscription: AnyCancellable?

    init(
        surface: any IslandSurfaceDriving,
        collapseDelay: @escaping @MainActor () -> Duration = {
            NookBridge.collapseDelay(forConfiguredSeconds: Defaults[.autoCollapseDelay])
        }
    ) {
        self.surface = surface
        self.collapseDelay = collapseDelay

        // Perch owns collapse timing, so the surface must not compact itself the instant
        // the cursor leaves. This replaces the old global `MouseEventMonitor`: hover now
        // comes from the surface's own tracking area, which hit-tests the visible notch
        // shape instead of a window rectangle, and needs no input monitoring at all.
        surface.staysExpandedOnHoverExit = true

        surface.onExpand = { [weak self] in self?.surfaceDidExpand() }
        surface.onCompact = { [weak self] in self?.surfaceDidCompact() }

        hoverSubscription = surface.isHoveringPublisher
            .removeDuplicates()
            .sink { [weak self] isHovering in
                self?.hoverDidChange(isHovering)
            }
    }

    deinit {
        collapseTask?.cancel()
    }

    // MARK: - Driving the surface

    /// Expands the surface and waits until the transition has settled.
    func expand() async {
        cancelScheduledCollapse()
        await surface.expand(on: nil)
    }

    /// Compacts the surface and waits until the transition has settled.
    func compact() async {
        cancelScheduledCollapse()
        await surface.compact(on: nil)
    }

    /// Switches the chrome between the pseudo-notch and floating looks.
    ///
    /// Safe to call while the surface is visible — the vendored surface rebuilds its
    /// window in place — so Settings can drive this live rather than deferring to the
    /// next launch. Window chrome is re-applied afterwards for the same reason it is
    /// re-applied on every transition: the rebuild produces a brand-new window.
    func applyChromeStyle(_ style: IslandChromeStyle) {
        surface.applyChromeStyle(style)
        applyWindowChrome()
    }

    // MARK: - Surface callbacks

    private func surfaceDidExpand() {
        isSurfaceExpanded = true
        applyWindowChrome()
        onSurfaceExpanded?()
    }

    private func surfaceDidCompact() {
        isSurfaceExpanded = false
        cancelScheduledCollapse()
        applyWindowChrome()
        onSurfaceCompacted?()
    }

    /// Re-applies the window-level settings the surface does not model.
    ///
    /// Called from *both* transition callbacks on purpose: the surface's panel fixes its
    /// collection behavior at construction and it builds a fresh window on every
    /// expand/compact, so anything applied once is silently lost on the next transition.
    func applyWindowChrome() {
        let behavior = Self.desiredCollectionBehavior(showInAllSpaces: Defaults[.showInAllSpaces])
        let applied = surface.configureWindow { window in
            window.collectionBehavior = behavior
        }
        if !applied {
            logger.debug("window chrome skipped — no live surface window")
        }
    }

    // MARK: - Auto-collapse

    private func hoverDidChange(_ isHovering: Bool) {
        if isHovering {
            cancelScheduledCollapse()
        } else if isSurfaceExpanded {
            scheduleCollapse()
        }
    }

    private func scheduleCollapse() {
        collapseTask?.cancel()
        let delay = collapseDelay()
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            await self.surface.compact(on: nil)
        }
    }

    private func cancelScheduledCollapse() {
        collapseTask?.cancel()
        collapseTask = nil
    }

    // MARK: - Pure policy

    /// Turns the persisted auto-collapse preference into a delay the scheduler can use.
    ///
    /// `Duration.seconds` traps on a non-finite `Double`, and the preference is a raw
    /// `Double` read from `Defaults` — so NaN and infinity are converted to the key's own
    /// declared default rather than crashing. Negative values clamp to zero, which is
    /// meaningful: collapse as soon as the cursor leaves.
    static func collapseDelay(forConfiguredSeconds seconds: Double) -> Duration {
        guard seconds.isFinite else { return .seconds(Defaults.Keys.autoCollapseDelay.defaultValue) }
        return .seconds(max(seconds, 0))
    }

    /// The collection behavior the island window must carry. `.canJoinAllSpaces` is the
    /// user-facing switch; the other three are non-negotiable for an overlay (never
    /// full-screen on its own, never cycled to with Cmd-`, follows the active space).
    nonisolated static func desiredCollectionBehavior(showInAllSpaces: Bool) -> NSWindow.CollectionBehavior {
        var behavior: NSWindow.CollectionBehavior = [.fullScreenAuxiliary, .stationary, .ignoresCycle]
        if showInAllSpaces {
            behavior.insert(.canJoinAllSpaces)
        }
        return behavior
    }

    /// The backdrop the surface should paint, reproducing Perch's current chrome: the
    /// `.hudWindow` vibrancy of `VibrancyBackground`, or a flat black fill when the user
    /// has asked the system to reduce transparency (where an `NSVisualEffectView` is both
    /// wasted work and against the accessibility setting's intent).
    ///
    /// Pure, but not `nonisolated`: `NookBackdrop`'s members inherit the project's default
    /// `MainActor` isolation, and the vendored source is off-limits to change. Callers are
    /// on the main actor anyway.
    static func makeBackdrop(reduceTransparency: Bool) -> NookBackdrop {
        guard !reduceTransparency else { return .solidBlack }
        return .vibrancy(
            NookBackdrop.Vibrancy(material: .hudWindow, blendingMode: .behindWindow, darkenOpacity: 0)
        )
    }
}
