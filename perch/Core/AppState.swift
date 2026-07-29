import Foundation
import Logging

@MainActor
@Observable
final class AppState {
    /// Derived, never assigned by a caller. The vendored surface is the source of truth for
    /// whether the island is expanded; this mirrors what the surface has *arrived at*, via
    /// the `applySurface…` methods below. Requests go the other way, through
    /// ``expand(to:)`` / ``collapse()``.
    private(set) var presentation: IslandPresentation = .compact

    /// `false` once the surface has torn its window down entirely.
    ///
    /// Deliberately separate from `presentation == .compact`. Hidden is not compact: there
    /// is no pill and no window, where compact still shows the chrome. Nothing in Perch
    /// asks the surface to hide today — there is no idle-hides-the-island path, by design —
    /// but the surface can still arrive there on its own, and folding that into `.compact`
    /// would leave the app believing it was showing a pill that does not exist.
    private(set) var isSurfaceVisible = true

    /// Which card the island shows when expanded.
    ///
    /// **Currently written but never read outside this type**, and that predates A5 — the
    /// expanded view has been preset-driven (it renders the active `PresetLayout`'s widgets
    /// by id) since the widget system landed, so no view has consulted `activeCard` or
    /// `IslandPresentation.card` at any point. Verified against the pre-A5 tree: the only
    /// `AppState` field the deleted chrome views read was `isPhysicalNotch`, which the
    /// chrome unification removed outright.
    ///
    /// Kept rather than deleted because Phase B's module bar selects *which* card is shown,
    /// which is exactly this. See the A6 hand-off.
    var activeCard: IslandCard = .idle
    var latestError: String?

    let presetStore = PresetStore()
    let widgetRegistry = WidgetRegistry()

    var openSettingsAction: (() -> Void)?

    let nowPlayingManager = NowPlayingManager()
    let aiUsageStore = AIUsageStore()
    let systemStatusMonitor = SystemStatusMonitor()

    private let logger = Logger(label: "com.tukuyomi032.perch.AppState")

    /// Drives the island surface expanded / compact. Injected by `AppDelegate` (which owns
    /// the `NookBridge`) rather than held as a `NookBridge` reference, so `AppState` stays
    /// testable without a live surface and the dependency keeps pointing one way.
    ///
    /// Each closure must not return until the transition has settled — `NookBridge`'s
    /// `expand()` / `compact()` both honour that.
    var driveSurfaceExpand: (@MainActor () async -> Void)?
    var driveSurfaceCompact: (@MainActor () async -> Void)?

    /// Tail of the serialized transition chain. See ``enqueueTransition(_:)``.
    private var transitionTask: Task<Void, Never>?

    /// What the *last request* asked for, as opposed to what the surface has arrived at.
    ///
    /// Requests are queued and settle asynchronously, so gating them on `presentation`
    /// would read a state one or more transitions out of date: a user who clicks to expand
    /// and immediately clicks to close would have the close dropped, because `presentation`
    /// is still `.compact` at the moment `collapse()` runs.
    private var requestedExpansion = false

    var isExpanded: Bool {
        presentation.expandsSurface
    }

    // MARK: - Requests

    /// Asks the surface to expand, showing `card`.
    ///
    /// `activeCard` is set synchronously so the expanded content is already correct by the
    /// time the surface renders it; `presentation` is not, because it only ever reflects
    /// where the surface has actually arrived (see ``applySurfaceExpanded()``).
    func expand(to card: IslandCard) {
        activeCard = card

        // Switching cards while already expanded is a content change, not a surface
        // transition. The surface would report nothing — its state is unchanged, and its
        // state publisher drops duplicates — so `presentation` has to pick up the new card
        // here or it would keep naming the old one.
        if presentation.expandsSurface {
            presentation = .expanded(card)
        }

        guard !requestedExpansion else { return }
        // Nothing to drive means nothing will happen, and setting the intent anyway would
        // break the invariant the flag exists for ("requestedExpansion is true only when a
        // transition is queued") — leaving the next click to read a stale intent and
        // collapse an island that never opened. Reachable at launch: `AppDelegate` builds
        // `MenuBarController` before `IslandHost`, so there is a window with no driver.
        guard driveSurfaceExpand != nil else {
            logger.debug("expand requested before the island surface was connected — ignoring")
            return
        }
        requestedExpansion = true
        logger.debug("Expanding island to card: \(card)")
        enqueueTransition { [weak self] in
            await self?.driveSurfaceExpand?()
        }
    }

    /// Opens the island if it is closed, closes it if it is open — the behaviour a click on
    /// the chrome has.
    ///
    /// Exists as its own method, rather than the caller branching on `isExpanded`, for two
    /// reasons. It is the only part of the click path that can be unit-tested (the gesture
    /// itself is an AppKit recognizer attached to a live window), and it branches on the
    /// same synchronous *intent* the requests below use rather than on `presentation` —
    /// clicking twice quickly must close, not re-open, and `presentation` has not caught up
    /// by the second click.
    func toggleExpansion(defaultCard: IslandCard = .nowPlaying) {
        if requestedExpansion {
            collapse()
        } else {
            expand(to: activeCard == .idle ? defaultCard : activeCard)
        }
    }

    /// Asks the surface to collapse back to the compact pill.
    func collapse() {
        guard requestedExpansion else { return }
        requestedExpansion = false
        logger.debug("Collapsing island")
        enqueueTransition { [weak self] in
            await self?.driveSurfaceCompact?()
        }
    }

    /// Runs surface transitions strictly one after another.
    ///
    /// The bridge's re-entrancy protection is a single flag pair, so overlapping
    /// `expand()` / `compact()` calls could defeat its filtering of the mid-conversion
    /// hide. Chaining each request onto the previous one means a user hammering the pill
    /// produces a queue rather than a pile-up, and the surface's own newest-wins generation
    /// counter resolves the rest.
    private func enqueueTransition(_ body: @escaping @MainActor () async -> Void) {
        enqueuedTransitionCount += 1
        let previous = transitionTask
        transitionTask = Task { @MainActor in
            await previous?.value
            await body()
        }
    }

    /// Number of transitions ever queued. Only used by ``settleTransitions()`` to tell
    /// "the chain finished" from "the chain finished and queued more work".
    private var enqueuedTransitionCount = 0

    /// Awaits the serialized transition chain until it is genuinely idle.
    ///
    /// A test seam, and deliberately not a fixed number of `Task.yield()`s: the number of
    /// hops a chain takes is an implementation detail of `enqueueTransition` and the driver
    /// closures, so a yield count is a flake waiting for someone to add a suspension point.
    /// Looping until no *new* work was queued is exact regardless.
    func settleTransitions() async {
        var lastSeen = -1
        while lastSeen != enqueuedTransitionCount {
            lastSeen = enqueuedTransitionCount
            await transitionTask?.value
        }
    }

    // MARK: - Surface state (one-way, from the surface)

    /// The surface has settled into its expanded state, from any cause — a request above,
    /// a hover, a file drag.
    ///
    /// Each of these resyncs ``requestedExpansion`` as well as `presentation`. The surface
    /// can expand or collapse on its own — a hover, a file drag, the bridge's auto-collapse
    /// timer — and leaving the intent flag stale would drop the user's *next* request: a
    /// `collapse()` after a hover-expand would find `requestedExpansion == false` and do
    /// nothing.
    func applySurfaceExpanded() {
        isSurfaceVisible = true
        requestedExpansion = true
        presentation = .expanded(activeCard)
    }

    /// The surface has settled into its compact pill.
    ///
    /// `activeCard` deliberately survives a collapse. It names the card the island shows
    /// *when* expanded, not a card it is showing right now, so it stays selected — which
    /// both makes reopening return to where the user was, and avoids a race: requests set
    /// `activeCard` synchronously but settle asynchronously, so clearing it here would let
    /// a collapse landing late wipe the card an already-queued expand had chosen.
    func applySurfaceCompacted() {
        isSurfaceVisible = true
        requestedExpansion = false
        presentation = .compact
    }

    /// The surface has gone away entirely — no pill, no window. See ``isSurfaceVisible``.
    func applySurfaceHidden() {
        isSurfaceVisible = false
        requestedExpansion = false
        presentation = .compact
    }
}
