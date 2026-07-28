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

    init(appState: AppState) {
        self.appState = appState

        // `.expandsOnHover` is deliberately absent. The bridge owns collapse timing so it
        // can honour the user's auto-collapse delay; letting the surface expand and compact
        // itself on hover would race that. `isHovering` still publishes without it, which
        // is what the bridge's timer listens to. `.keepVisible` stops a hide animation from
        // stealing the surface out from under a cursor that is on it.
        //
        // Erased to `AnyView` so the generic parameters do not spread into this type's
        // stored properties and from there into every signature that touches it.
        let nook = Nook<AnyView, AnyView, AnyView>(
            hoverBehavior: [.keepVisible],
            style: .standard,
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

        connectStateFlow()
        applyInitialConfiguration()
        observePreferences()
        observeReduceTransparency()

        // The surface starts hidden; nothing shows it implicitly.
        Task { await bridge.compact() }
    }

    deinit {
        chromeStyleObservation?.invalidate()
        allSpacesObservation?.invalidate()
        screenPreferenceObservation?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Wiring

    /// Connects the two directions. `AppState` gets closures that drive the surface;
    /// the surface gets callbacks that report where it actually arrived.
    private func connectStateFlow() {
        appState.driveSurfaceExpand = { [bridge] in await bridge.expand() }
        appState.driveSurfaceCompact = { [bridge] in await bridge.compact() }

        bridge.onSurfaceExpanded = { [weak appState] in appState?.applySurfaceExpanded() }
        bridge.onSurfaceCompacted = { [weak appState] in appState?.applySurfaceCompacted() }
        // Kept distinct from compacted on purpose — hidden means no pill and no window,
        // which is a different thing for `AppState` to believe than "showing the pill".
        bridge.onSurfaceHidden = { [weak appState] in appState?.applySurfaceHidden() }
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

        // `screenProvider` reads the preference on each call, so the surface only needs a
        // nudge to move: re-applying the current chrome style rebuilds the window on the
        // newly-resolved screen.
        screenPreferenceObservation = Defaults.observe(.islandScreenPreference) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.bridge.applyChromeStyle(Defaults[.islandChromeStyle])
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
