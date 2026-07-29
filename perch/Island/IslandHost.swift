import AppKit
import Defaults
import Logging
import SwiftUI

private let logger = Logger(label: "com.tukuyomi032.perch.IslandHost")

/// Owns the island: the vendored surface, the `NookBridge` that applies Perch's policy to
/// it, and the preference / accessibility observers that keep both in sync.
///
/// This is what `IslandWindowController` became. The controller computed frames, animated
/// the window, tracked transition direction and mirrored sizes back into `AppState`; the
/// surface owns all of that now. What is left is composition — build the surface, connect
/// it to `AppState` in both directions, and re-apply the handful of settings the surface
/// has no opinion about.
///
/// **Direction of flow.** Requests go down (`AppState.driveSurface*` → `NookBridge` →
/// surface); state comes back up (surface → bridge callbacks → `AppState.applySurface*`).
/// State is never taken from the return of an `await`: `NookBridge.compact()` can settle as
/// hidden rather than compact, and a chrome-style change rebuilds the window in a way that
/// supersedes an in-flight transition, so an awaited call can return without having
/// arrived. The callbacks are the only trustworthy signal.
@MainActor
final class IslandHost {
    private let appState: AppState
    private let surface: Nook<AnyView, AnyView, AnyView>
    private let bridge: NookBridge

    // `nonisolated(unsafe)`: written once on the main actor during `init` and read only in
    // the nonisolated `deinit`, so no concurrent access is possible. Same reasoning — and
    // same `Defaults.Observation` non-Sendability — as the observation `IslandWindowController`
    // held before this type replaced it.
    nonisolated(unsafe) private var chromeStyleObservation: (any Defaults.Observation)?
    nonisolated(unsafe) private var allSpacesObservation: (any Defaults.Observation)?
    nonisolated(unsafe) private var screenPreferenceObservation: (any Defaults.Observation)?
    nonisolated(unsafe) private var screenChangeObserver: (any NSObjectProtocol)?

    /// One recognizer, reused for the host's lifetime. The surface tears its window down
    /// and builds a new one on every transition, so the recognizer has to be re-attached
    /// constantly; holding a single instance makes re-attaching idempotent by construction,
    /// where building one per attach would stack duplicates and fire the toggle N times per
    /// click.
    private lazy var tapRecognizer: NSClickGestureRecognizer = {
        let recognizer = NSClickGestureRecognizer(target: self, action: #selector(islandWasClicked))
        recognizer.numberOfClicksRequired = 1
        return recognizer
    }()

    init(appState: AppState) {
        self.appState = appState

        // `.expandsOnHover` is deliberately absent. The vendored flag converts instantly
        // with zero debounce; `NookBridge` drives its own debounced hover-to-expand instead
        // (see its `scheduleExpand()`), the same way it already owns collapse timing so it
        // can honour the user's auto-collapse delay. `isHovering` still publishes without
        // the flag, which is what both of the bridge's timers listen to. `.keepVisible`
        // stops a hide animation from stealing the surface out from under a cursor that is
        // on it.
        //
        // `compactTopCornerRadius`/`compactBottomCornerRadius` round the compact pill
        // further than the vendored default (6, 14) — an Atoll-inspired look. Values are a
        // starting point pending the vfr-derived animation pass (see
        // docs/SwiftUI-Animation-Architecture-Handbook-ja.md task 9 in the Phase B plan).
        //
        // Erased to `AnyView` so the generic parameters do not spread into this type's
        // stored properties and from there into every signature that touches it.
        let nook = Nook<AnyView, AnyView, AnyView>(
            hoverBehavior: [.keepVisible],
            style: NookStyle(
                topCornerRadius: NookStyle.standard.topCornerRadius,
                bottomCornerRadius: NookStyle.standard.bottomCornerRadius,
                compactTopCornerRadius: 10,
                compactBottomCornerRadius: 20
            ),
            expanded: { AnyView(ExpandedIslandView().environment(appState)) },
            compactLeading: { AnyView(IslandCompactLeading().environment(appState)) },
            compactTrailing: { AnyView(IslandCompactTrailing().environment(appState)) }
        )
        self.surface = nook
        self.bridge = NookBridge(surface: nook)

        // Replaces the bridge's default, which reaches for `NSScreen.perchPreferredScreen`
        // — a `NotchDetector` extension that is on its way out. Resolved on every call
        // rather than captured, so unplugging the chosen display degrades through
        // `ScreenLocator`'s fallback chain instead of stranding the island.
        bridge.screenProvider = { ScreenLocator.screen(matching: Defaults[.islandScreenPreference]) }

        installWindowConfigurator()
        connectStateFlow()
        applyInitialConfiguration()
        observePreferences()
        observeReduceTransparency()
        observeScreenChanges()

        // The surface starts hidden; nothing shows it implicitly. The click recognizer is
        // installed by the configurator when this produces a window.
        Task { await bridge.compact() }
    }

    deinit {
        chromeStyleObservation?.invalidate()
        allSpacesObservation?.invalidate()
        screenPreferenceObservation?.invalidate()
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
        }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Wiring

    /// Connects the two directions. `AppState` gets closures that drive the surface;
    /// the surface gets callbacks that report where it actually arrived.
    ///
    /// The bridge is captured weakly on the way down. The surface's content views hold
    /// `AppState` strongly (they are handed it via `.environment`), so a strong capture
    /// here would close the loop `AppState` → bridge → surface → content → `AppState`.
    /// Both ends live for the lifetime of the app today, so nothing would actually leak —
    /// but the cycle would quietly outlive any future change that made the island
    /// tear-downable, which is a worse bug to find later than to prevent now.
    private func connectStateFlow() {
        appState.driveSurfaceExpand = { [weak bridge] in await bridge?.expand() }
        appState.driveSurfaceCompact = { [weak bridge] in await bridge?.compact() }

        bridge.onSurfaceExpanded = { [weak appState] in appState?.applySurfaceExpanded() }
        bridge.onSurfaceCompacted = { [weak appState] in appState?.applySurfaceCompacted() }
        // Kept distinct from compacted on purpose — hidden means no pill and no window,
        // which is a different thing for `AppState` to believe than "showing the pill".
        bridge.onSurfaceHidden = { [weak self] in self?.appState.applySurfaceHidden() }
    }

    private func applyInitialConfiguration() {
        bridge.applyChromeStyle(Defaults[.islandChromeStyle])
        bridge.applyBackdrop(reduceTransparency: Self.reduceTransparencyIsOn)
        logger.info(
            "island host started",
            metadata: [
                "chromeStyle": .string(Defaults[.islandChromeStyle].rawValue),
                "screenPreference": .string(Defaults[.islandScreenPreference].mode.rawValue),
            ])
    }

    // MARK: - Preferences

    private func observePreferences() {
        // Rebuilds the surface's window in place, so a switch takes effect immediately
        // rather than on next launch. Routed through the bridge so window chrome is
        // re-applied afterwards — the rebuild produces a brand-new window.
        chromeStyleObservation = Defaults.observe(.islandChromeStyle) { [weak self] change in
            Task { @MainActor [weak self] in
                self?.bridge.applyChromeStyle(change.newValue)
            }
        }

        // `NookPanel` fixes its collection behavior at init, so the preference has to be
        // re-applied to the live window rather than merely stored.
        allSpacesObservation = Defaults.observe(.showInAllSpaces) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.bridge.applyWindowChrome()
            }
        }

        // `screenProvider` reads the preference on each call, so the surface only needs to
        // be told to rebuild. It must be `relocate()`, not a re-application of the current
        // chrome style: the surface rebuilds on a style change only when the style actually
        // *changes*, so re-applying the same value is a silent no-op and the island would
        // never move.
        screenPreferenceObservation = Defaults.observe(.islandScreenPreference) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.bridge.relocate()
            }
        }
    }

    // MARK: - Click target

    /// Makes the whole visible chrome open and close the island.
    ///
    /// An AppKit recognizer on the surface's content view, rather than a SwiftUI
    /// `.onTapGesture` on Perch's own content, because in compact mode Perch only supplies
    /// the two slots that flank the notch — the gap between them is drawn by the vendored
    /// view and is not Perch's to attach a gesture to. In `.notch` chrome on a Mac with no
    /// physical notch that gap is the 195pt pseudo-notch, i.e. most of what the user sees
    /// and the most obvious thing to click. Worse, Q2 keeps the chrome on screen while idle,
    /// where both slots collapse to zero size and a SwiftUI gesture would have no hit area
    /// at all — exactly the state in which opening the island matters most, since the
    /// expanded view is where the widgets live.
    ///
    /// Attaching to the content view rather than the window is what keeps this honest: the
    /// panel spans a large region, but the vendored view applies `.contentShape(NookShape)`,
    /// which constrains AppKit hit-testing as well as drawing. The hosting view therefore
    /// returns no hit outside the visible shape, so clicks on the transparent area still
    /// pass through to whatever is behind — the recognizer only ever sees clicks on the
    /// chrome itself.
    /// Registered once, as the bridge's per-window configurator, rather than called from
    /// each site that can produce a new window. Enumerating those sites by hand is what an
    /// earlier version did, and it is a losing game: both transition callbacks, both
    /// `apply…` rebuilds, `relocate()`, and the screen-parameter observer all qualify, a
    /// missed one leaves the recognizer on a dead panel — a *silently unclickable island* —
    /// and nothing anywhere reports it. Hanging it off `applyWindowChrome()`, which the
    /// bridge already calls from every one of those paths, makes "forgot to re-attach"
    /// unrepresentable.
    private func installWindowConfigurator() {
        bridge.windowConfigurator = { [tapRecognizer] window in
            Self.attach(tapRecognizer, to: window)
        }
    }

    /// Moves `recognizer` onto `window`'s content view, detaching it from wherever it was.
    ///
    /// Split out of the configurator closure so it can be tested: everything it needs is an
    /// `NSWindow` and a recognizer, neither of which requires a screen or a live surface,
    /// while `IslandHost` itself cannot be built in a test without mounting a real panel.
    /// The two properties worth pinning are both silent when broken — a re-attach that
    /// stacked a second recognizer would fire the toggle twice per click, and a move that
    /// failed to detach would leave the island responding to clicks on a dead panel.
    static func attach(_ recognizer: NSGestureRecognizer, to window: NSWindow) {
        guard let contentView = window.contentView,
            recognizer.view !== contentView
        else { return }
        recognizer.view?.removeGestureRecognizer(recognizer)
        contentView.addGestureRecognizer(recognizer)
    }

    @objc private func islandWasClicked() {
        appState.toggleExpansion()
    }

    /// Brings the island back if it has no window.
    ///
    /// `Nook.compact(on:)` returns silently when no screen resolves, and the surface's own
    /// screen observer only tears the window *down* while hidden — it never restores it. So
    /// a launch that raced display configuration, or a moment with no attached display,
    /// would otherwise leave the island gone until the app is relaunched. The old
    /// `IslandWindowController` force-unwrapped `NSScreen.main` here: it could crash, but it
    /// could not silently disappear.
    ///
    /// Gated on `AppState.isSurfaceVisible` as well as on the missing window, because the
    /// two reasons a window can be absent are opposite: the island *failed* to appear
    /// (restore it) or the island was *dismissed* (leave it alone). `hasLiveWindow` cannot
    /// tell them apart. No hide path is reachable today, so this changes nothing now — it
    /// fixes the intent in place, before a future `hide()` turns "restore on every display
    /// change" into an island the user cannot get rid of.
    private func restoreSurfaceIfLost() {
        guard appState.isSurfaceVisible, !bridge.hasLiveWindow else { return }
        logger.info("island has no window — re-showing")
        Task { await bridge.compact() }
    }

    /// A display change rebuilds the window without a state transition, so neither
    /// transition callback fires. The bridge re-applies chrome (and with it this host's
    /// configurator) on that notification already; what is left for the host is noticing
    /// that the island has no window at all and bringing it back.
    private func observeScreenChanges() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.restoreSurfaceIfLost()
            }
        }
    }

    // MARK: - Accessibility

    private static var reduceTransparencyIsOn: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    /// Repaints the backdrop when the user toggles Reduce Transparency. Without this the
    /// setting is only honoured at launch, so turning it on leaves a vibrancy layer the
    /// accessibility setting explicitly asks not to be drawn.
    private func observeReduceTransparency() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayDidChange),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    @objc private func accessibilityDisplayDidChange() {
        bridge.applyBackdrop(reduceTransparency: Self.reduceTransparencyIsOn)
    }
}
