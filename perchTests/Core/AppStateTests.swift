import Foundation
import Testing

@testable import perch

@Suite("AppState", .serialized)
@MainActor
struct AppStateTests {
    /// Stands in for `NookBridge`: records the requests `AppState` makes, and reports back
    /// through the same `applySurface…` entry points the real bridge's callbacks use.
    ///
    /// The reporting is what the tests are really about. `AppState` deliberately does *not*
    /// derive its state from the return of `driveSurfaceExpand` — the bridge can settle as
    /// hidden rather than expanded, and a chrome-style change can supersede an in-flight
    /// transition so it returns without arriving. State only ever moves on a callback.
    @MainActor
    private final class FakeSurfaceDriver {
        private(set) var expandCount = 0
        private(set) var compactCount = 0
        /// Records interleaving, so a test can prove two transitions did not overlap.
        private(set) var log: [String] = []

        func attach(to appState: AppState, reporting: Bool = true) {
            appState.driveSurfaceExpand = { [weak appState] in
                self.expandCount += 1
                self.log.append("expand:start")
                await Task.yield()
                self.log.append("expand:end")
                if reporting { appState?.applySurfaceExpanded() }
            }
            appState.driveSurfaceCompact = { [weak appState] in
                self.compactCount += 1
                self.log.append("compact:start")
                await Task.yield()
                self.log.append("compact:end")
                if reporting { appState?.applySurfaceCompacted() }
            }
        }
    }

    /// Lets the serialized transition chain drain. `enqueueTransition` awaits the previous
    /// task, so a handful of yields covers a couple of chained transitions.
    private func drain() async {
        for _ in 0..<10 { await Task.yield() }
    }

    @Test("a fresh AppState is compact and visible")
    func startsCompact() {
        let appState = AppState()
        #expect(appState.presentation == .compact)
        #expect(appState.isExpanded == false)
        #expect(appState.isSurfaceVisible == true)
    }

    @Test("expand(to:) sets activeCard synchronously so content is ready before the surface renders")
    func expandSetsActiveCardImmediately() {
        let appState = AppState()
        FakeSurfaceDriver().attach(to: appState)
        appState.expand(to: .nowPlaying)
        #expect(appState.activeCard == .nowPlaying)
    }

    @Test("expand(to:) does not move presentation until the surface reports back")
    func expandDoesNotAnticipateTheSurface() async {
        let appState = AppState()
        let driver = FakeSurfaceDriver()
        driver.attach(to: appState, reporting: false)

        appState.expand(to: .nowPlaying)
        await drain()

        #expect(driver.expandCount == 1)
        // The surface never arrived, so neither did the state.
        #expect(appState.presentation == .compact)
        #expect(appState.isExpanded == false)
    }

    @Test("expand(to:) reaches .expanded once the surface reports it")
    func expandReachesExpanded() async {
        let appState = AppState()
        FakeSurfaceDriver().attach(to: appState)

        appState.expand(to: .nowPlaying)
        await drain()

        #expect(appState.presentation == .expanded(.nowPlaying))
        #expect(appState.isExpanded == true)
    }

    @Test("collapse() returns to .compact and clears the active card")
    func collapseReturnsToCompact() async {
        let appState = AppState()
        FakeSurfaceDriver().attach(to: appState)

        appState.expand(to: .nowPlaying)
        await drain()
        appState.collapse()
        await drain()

        #expect(appState.presentation == .compact)
        #expect(appState.isExpanded == false)
        // `activeCard` is a sticky selection, not a live state — collapsing keeps it so
        // reopening returns to the same card.
        #expect(appState.activeCard == .nowPlaying)
    }

    @Test("collapse() on an already-compact island never touches the surface")
    func collapseOnCompactIsNoOp() async {
        let appState = AppState()
        let driver = FakeSurfaceDriver()
        driver.attach(to: appState)

        appState.collapse()
        await drain()

        #expect(driver.compactCount == 0)
        #expect(appState.presentation == .compact)
    }

    @Test("rapid toggling serializes — transitions never overlap")
    func rapidTogglingIsSerialized() async {
        let appState = AppState()
        let driver = FakeSurfaceDriver()
        driver.attach(to: appState)

        appState.expand(to: .nowPlaying)
        appState.collapse()
        appState.expand(to: .aiUsage)
        await drain()

        // Each transition must fully close before the next opens. Overlap would let the
        // bridge's single-flag hide filter misclassify a mid-conversion dip as a real hide.
        #expect(
            driver.log == [
                "expand:start", "expand:end",
                "compact:start", "compact:end",
                "expand:start", "expand:end",
            ])
        #expect(appState.presentation == .expanded(.aiUsage))
    }

    @Test("a surface-initiated expand (hover, drag) is reflected without any request")
    func surfaceInitiatedExpandIsReflected() {
        let appState = AppState()
        appState.activeCard = .nowPlaying
        appState.applySurfaceExpanded()
        #expect(appState.presentation == .expanded(.nowPlaying))
    }

    @Test("a hidden surface is not reported as compact")
    func hiddenIsDistinctFromCompact() {
        let appState = AppState()
        appState.applySurfaceHidden()
        #expect(appState.isSurfaceVisible == false)
        #expect(appState.presentation == .compact)

        // ...and coming back clears it again.
        appState.applySurfaceCompacted()
        #expect(appState.isSurfaceVisible == true)
    }

    @Test("collapse() after a surface-initiated expand is honoured")
    func collapseAfterHoverExpandIsHonoured() async {
        let appState = AppState()
        let driver = FakeSurfaceDriver()
        driver.attach(to: appState)

        // The surface expanded by itself (hover / drag) — no request went through AppState.
        appState.applySurfaceExpanded()
        appState.collapse()
        await drain()

        #expect(driver.compactCount == 1)
        #expect(appState.presentation == .compact)
    }

    @Test("switching cards while expanded updates the card without a surface transition")
    func switchingCardsWhileExpandedDoesNotRetransition() async {
        let appState = AppState()
        let driver = FakeSurfaceDriver()
        driver.attach(to: appState)

        appState.expand(to: .nowPlaying)
        await drain()
        appState.expand(to: .aiUsage)
        await drain()

        // The surface is already expanded, so it is not driven a second time — it would
        // report nothing anyway, its state being unchanged.
        #expect(driver.expandCount == 1)
        #expect(appState.presentation == .expanded(.aiUsage))
    }

    @Test("expandedWindowHeight follows active preset widget sizes (not a card-card constant)")
    func expandedWindowHeightFollowsActivePreset() {
        let appState = AppState()
        // Default Daily preset = NowPlaying standard (264) + AIUsage compact (52),
        // one widget in .sidebar => header 40 + widgets 316 + divider 1 = 357
        #expect(appState.expandedWindowHeight == 357)
    }

    @Test("expandedWindowHeight ignores activeCard once preset-driven")
    func expandedWindowHeightIgnoresActiveCard() {
        let appState = AppState()
        let baseline = appState.expandedWindowHeight
        appState.expand(to: .nowPlaying)
        // Even with activeCard == .nowPlaying, height must come from the preset.
        #expect(appState.expandedWindowHeight == baseline)
    }
}
