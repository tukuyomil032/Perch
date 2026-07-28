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
/// `onSurfaceExpanded` / `onSurfaceCompacted` / `onSurfaceHidden` closures instead. Two
/// reasons: the surface, not Perch, is about to become the source of truth for expansion
/// state (A5 turns `AppState.presentation` into a one-way derivation of exactly these
/// callbacks), and a bridge that reached into `AppState` would make it impossible to test
/// either side without dragging the other in. The bridge also deliberately holds no
/// reference to `AppState.transitionGeneration`, the 110ms/500ms timers, or the
/// `.expanding` / `.collapsing` presentation cases — all four are slated for deletion in
/// A5 because the surface already provides the equivalent.
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

    /// How the scheduled collapse waits. Injectable so tests control the release point
    /// exactly instead of racing a wall-clock sleep.
    private let sleep: @Sendable (Duration) async throws -> Void

    /// Called when the surface has settled into its expanded / compact state, from any
    /// cause — a `NookBridge.expand()`, a hover, a file drag.
    var onSurfaceExpanded: (@MainActor () -> Void)?
    var onSurfaceCompacted: (@MainActor () -> Void)?

    /// Called when the surface has gone away entirely.
    ///
    /// Kept distinct from `onSurfaceCompacted` on purpose. Hidden is not compact: there is
    /// no pill on screen and no window at all, so a host that collapsed the two would show
    /// "compact island" UI for a surface the user has dismissed. It matters beyond an
    /// explicit `hide()`, because a surface configured without compact content turns
    /// `compact()` into a hide — so `NookBridge.compact()` can legitimately return having
    /// fired *this* callback and not `onSurfaceCompacted`. A5's `AppState` should treat
    /// both as "not expanded" and use this one to drop the island entirely.
    var onSurfaceHidden: (@MainActor () -> Void)?

    /// Resolves which display the island lives on. `IslandWindowController` did this with
    /// `NSScreen.perchPreferredScreen`; the surface has the same seam, so the preference
    /// is forwarded rather than reimplemented. A5 replaces the default below with the
    /// persisted `ScreenPreference` resolved through `ScreenLocator`.
    var screenProvider: (@MainActor () -> NSScreen?)? {
        get { surface.screenProvider }
        set { surface.screenProvider = newValue }
    }

    private var isSurfaceExpanded = false
    private var collapseTask: Task<Void, Never>?
    private var hoverSubscription: AnyCancellable?
    private var screenChangeSubscription: AnyCancellable?

    init(
        surface: any IslandSurfaceDriving,
        collapseDelay: @escaping @MainActor () -> Duration = {
            NookBridge.collapseDelay(forConfiguredSeconds: Defaults[.autoCollapseDelay])
        },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.surface = surface
        self.collapseDelay = collapseDelay
        self.sleep = sleep

        // Perch owns collapse timing, so the surface must not compact itself the instant
        // the cursor leaves. This replaces the old global `MouseEventMonitor`: hover now
        // comes from the surface's own tracking area, which hit-tests the visible notch
        // shape instead of a window rectangle, and needs no input monitoring at all.
        surface.staysExpandedOnHoverExit = true

        // Preserves `IslandWindowController`'s display choice (built-in display first,
        // system main as fallback) so vendoring does not silently move the island onto a
        // different monitor. A5 replaces this with the persisted `ScreenPreference`
        // resolved through `ScreenLocator`, at which point `NotchDetector` can go.
        surface.screenProvider = { NSScreen.perchPreferredScreen }

        surface.onExpand = { [weak self] in self?.surfaceDidExpand() }
        surface.onCompact = { [weak self] in self?.surfaceDidCompact() }
        surface.onHide = { [weak self] in self?.surfaceDidHide() }

        hoverSubscription = surface.isHoveringPublisher
            .removeDuplicates()
            .sink { [weak self] isHovering in
                self?.hoverDidChange(isHovering)
            }

        // A display change is the fourth way the surface's window gets replaced, and the
        // only one that does not go through a state transition: the surface rebuilds the
        // window in place on `didChangeScreenParameters` while staying expanded/compact,
        // so neither `onExpand` nor `onCompact` fires and the fresh panel carries the
        // vendored defaults. Without this, unplugging a display silently re-enables
        // `.canJoinAllSpaces` for a user who turned it off.
        screenChangeSubscription = NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // Both observers hang off the same notification on the main run loop, and
                // the surface's rebuild must land first — otherwise chrome is applied to
                // the window that is about to be replaced. Yielding puts this behind it.
                Task { @MainActor [weak self] in
                    await Task.yield()
                    self?.applyWindowChrome()
                }
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
    ///
    /// May settle as *hidden* rather than compact — see ``onSurfaceHidden``.
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

    /// Sets the pseudo-notch width. Rebuilds a visible window in place, so window chrome
    /// is re-applied for the same reason as ``applyChromeStyle(_:)``.
    func applySyntheticNotchWidth(_ width: CGFloat) {
        surface.applySyntheticNotchWidth(width)
        applyWindowChrome()
    }

    /// Repaints the chrome backdrop for the current Reduce Transparency setting. Does not
    /// rebuild the window, so no chrome re-application is needed.
    func applyBackdrop(reduceTransparency: Bool) {
        surface.applyBackdrop(reduceTransparency: reduceTransparency)
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

    private func surfaceDidHide() {
        // Must clear the expansion flag: the hidden transition also publishes
        // `isHovering = false`, and without this the hover handler would read that as
        // "cursor left an expanded surface", schedule a collapse, and the eventual
        // `compact()` would build a *new* window — resurrecting an island the user just
        // dismissed.
        isSurfaceExpanded = false
        cancelScheduledCollapse()
        onSurfaceHidden?()
    }

    /// Re-applies the window-level settings the vendored panel does not carry.
    ///
    /// Internal rather than private because the settings it restores are preference-driven:
    /// A5 calls it from the `showInAllSpaces` `Defaults` observer so a toggle takes effect
    /// without waiting for the next transition.
    ///
    /// Called from every path that can produce a new window — both transition callbacks,
    /// the two `apply…` rebuilds, and the screen-parameter observer — because the surface
    /// builds a fresh panel each time and anything applied once is otherwise lost.
    ///
    /// **Audit against the window `IslandWindow` used to build** (`level`, `hasShadow`,
    /// `backgroundColor`, `tabbingMode`, `isMovableByWindowBackground` are all either
    /// matched or intentionally left to the vendored panel):
    /// - `level`: the panel sits at `.statusBar + 8` where `IslandWindow` used
    ///   `.statusWindow + 1`. Accepted, not overridden — both float above the menu bar,
    ///   and the vendored value is the one its drag pipeline is tuned for (`.screenSaver`
    ///   and above silently drops system drag sessions).
    /// - `tabbingMode` / `isMovableByWindowBackground`: accepted. A borderless `NSPanel`
    ///   is not tab-eligible, and background-dragging is already off by default.
    /// - `isOpaque` / `isReleasedWhenClosed`: overridden below. The panel leaves both at
    ///   their defaults, and the surface calls `close()` on teardown, so
    ///   `isReleasedWhenClosed` decides whether that `close()` can free a window the
    ///   surface still references.
    func applyWindowChrome() {
        let behavior = Self.desiredCollectionBehavior(showInAllSpaces: Defaults[.showInAllSpaces])
        let applied = surface.configureWindow { window in
            window.collectionBehavior = behavior
            window.isOpaque = false
            window.isReleasedWhenClosed = false
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
            try? await self?.sleep(delay)
            // `isSurfaceExpanded` is re-checked *after* the wait, not just before it:
            // cancellation does not reach into `surface.compact`, so the state check is
            // the only thing that stops a collapse whose reason disappeared while it
            // waited (the surface was hidden, or compacted by something else).
            guard !Task.isCancelled, let self, self.isSurfaceExpanded else { return }
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
    /// The decision lives here, in Perch; the assignment lives in
    /// `Nook.applyBackdrop(reduceTransparency:)`, which is the only place the `NookBackdrop`
    /// type is touched. Pure, but not `nonisolated`: `NookBackdrop`'s members inherit the
    /// project's default `MainActor` isolation and the vendored source is off-limits.
    static func makeBackdrop(reduceTransparency: Bool) -> NookBackdrop {
        guard !reduceTransparency else { return .solidBlack }
        return .vibrancy(
            NookBackdrop.Vibrancy(material: .hudWindow, blendingMode: .behindWindow, darkenOpacity: 0)
        )
    }
}
