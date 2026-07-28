import AppKit
import Defaults
import Foundation
import Testing

@testable import perch

/// Stands in for `Task.sleep` so the scheduled collapse is released by the test rather
/// than by the wall clock. Negative assertions ("no collapse happened") are only
/// meaningful this way: with a real sleep they pass whenever the machine is slow, which
/// is exactly when a regression would slip through.
@MainActor
final class ManualSleeper {
    private var pending: [CheckedContinuation<Void, Never>] = []
    private(set) var sleepCallCount = 0
    private(set) var requestedDurations: [Duration] = []

    func sleep(_ duration: Duration) async {
        sleepCallCount += 1
        requestedDurations.append(duration)
        await withCheckedContinuation { pending.append($0) }
    }

    /// Lets every waiting sleeper return.
    func releaseAll() {
        let waiting = pending
        pending = []
        waiting.forEach { $0.resume() }
    }
}

/// `.serialized` because one test posts `didChangeScreenParametersNotification`, which
/// `NotificationCenter.default` delivers to every live bridge in the process — including
/// ones belonging to tests running in parallel.
@Suite("NookBridge", .serialized)
@MainActor
struct NookBridgeTests {

    /// Builds a bridge whose collapse timing is fully under the test's control.
    private func makeBridge(
        surface: FakeIslandSurface,
        sleeper: ManualSleeper,
        delay: Duration = .seconds(3),
        showInAllSpaces: Bool = true
    ) -> NookBridge {
        NookBridge(
            surface: surface,
            collapseDelay: { delay },
            showInAllSpaces: { showInAllSpaces },
            sleep: { duration in await sleeper.sleep(duration) }
        )
    }

    /// Lets queued main-actor work (the bridge's collapse task, its screen-change hop)
    /// run to completion before the assertion.
    private func settle(_ iterations: Int = 8) async {
        for _ in 0..<iterations { await Task.yield() }
    }

    // MARK: - collapseDelay

    @Test("the configured delay passes through unchanged")
    func collapseDelayPassesThrough() {
        #expect(NookBridge.collapseDelay(forConfiguredSeconds: 3) == .seconds(3))
        #expect(NookBridge.collapseDelay(forConfiguredSeconds: 0.5) == .seconds(0.5))
    }

    @Test("zero means collapse as soon as the cursor leaves, not 'never'")
    func collapseDelayZeroIsAllowed() {
        #expect(NookBridge.collapseDelay(forConfiguredSeconds: 0) == .zero)
    }

    @Test("a negative delay clamps to zero instead of underflowing the scheduler")
    func collapseDelayNegativeClamps() {
        #expect(NookBridge.collapseDelay(forConfiguredSeconds: -5) == .zero)
    }

    @Test("non-finite values fall back to the preference's own default, not a second one")
    func collapseDelayNonFinite() {
        let fallback = Duration.seconds(Defaults.Keys.autoCollapseDelay.defaultValue)
        #expect(NookBridge.collapseDelay(forConfiguredSeconds: .nan) == fallback)
        #expect(NookBridge.collapseDelay(forConfiguredSeconds: .infinity) == fallback)
    }

    // MARK: - desiredCollectionBehavior

    @Test("showInAllSpaces adds .canJoinAllSpaces on top of the overlay baseline")
    func collectionBehaviorAllSpaces() {
        let behavior = NookBridge.desiredCollectionBehavior(showInAllSpaces: true)
        #expect(behavior.contains(.canJoinAllSpaces))
        #expect(behavior.contains(.fullScreenAuxiliary))
        #expect(behavior.contains(.stationary))
        #expect(behavior.contains(.ignoresCycle))
    }

    @Test("the overlay baseline survives when showInAllSpaces is off")
    func collectionBehaviorSingleSpace() {
        let behavior = NookBridge.desiredCollectionBehavior(showInAllSpaces: false)
        #expect(!behavior.contains(.canJoinAllSpaces))
        #expect(behavior.contains(.fullScreenAuxiliary))
        #expect(behavior.contains(.stationary))
        #expect(behavior.contains(.ignoresCycle))
    }

    // MARK: - makeBackdrop

    @Test("the default backdrop is the hudWindow vibrancy Perch renders today")
    func backdropVibrancy() throws {
        guard case .vibrancy(let vibrancy) = NookBridge.makeBackdrop(reduceTransparency: false) else {
            Issue.record("expected a vibrancy backdrop")
            return
        }
        #expect(vibrancy.material == .hudWindow)
        #expect(vibrancy.blendingMode == .behindWindow)
    }

    @Test("Reduce Transparency drops the visual effect view entirely")
    func backdropReduceTransparency() {
        guard case .solid = NookBridge.makeBackdrop(reduceTransparency: true) else {
            Issue.record("expected a solid backdrop when transparency is reduced")
            return
        }
    }

    @Test("the transparency setting reaches the surface through the bridge")
    func backdropReachesSurface() {
        let surface = FakeIslandSurface()
        let bridge = makeBridge(surface: surface, sleeper: ManualSleeper())

        bridge.applyBackdrop(reduceTransparency: true)
        bridge.applyBackdrop(reduceTransparency: false)

        #expect(surface.appliedBackdropReduceTransparency == [true, false])
    }

    // MARK: - Surface driving (via the fake)

    @Test("the bridge takes over collapse timing and turns off the mid-conversion blink")
    func bridgeOwnsCollapseTiming() {
        let surface = FakeIslandSurface()
        _ = makeBridge(surface: surface, sleeper: ManualSleeper())
        #expect(surface.staysExpandedOnHoverExit)
        #expect(surface.skipsIntermediateHides)
    }

    @Test("a display preference is installed by default and can be replaced")
    func screenProviderIsWired() {
        let surface = FakeIslandSurface()
        let bridge = makeBridge(surface: surface, sleeper: ManualSleeper())

        // Without this the surface silently falls back to the system main screen and the
        // preferred-display logic is dead code.
        #expect(surface.screenProvider != nil)

        bridge.screenProvider = { nil }
        #expect(bridge.screenProvider != nil)
    }

    @Test("expand() and compact() reach the surface and settle before returning")
    func expandAndCompactReachSurface() async {
        let surface = FakeIslandSurface()
        let bridge = makeBridge(surface: surface, sleeper: ManualSleeper())

        await bridge.expand()
        #expect(surface.expandCallCount == 1)
        #expect(surface.state == .expanded)

        await bridge.compact()
        #expect(surface.compactCallCount == 1)
        #expect(surface.state == .compact)
    }

    @Test("surface transitions are forwarded to the host callbacks")
    func transitionsAreForwarded() async {
        let surface = FakeIslandSurface()
        let bridge = makeBridge(surface: surface, sleeper: ManualSleeper())
        var expandedCount = 0
        var compactedCount = 0
        bridge.onSurfaceExpanded = { expandedCount += 1 }
        bridge.onSurfaceCompacted = { compactedCount += 1 }

        await bridge.expand()
        await bridge.compact()

        #expect(expandedCount == 1)
        #expect(compactedCount == 1)
    }

    // MARK: - Window chrome

    @Test("a user who turned off all-Spaces keeps it through every window rebuild")
    func chromeIsReappliedOnEveryTransition() async {
        let surface = FakeIslandSurface()
        let bridge = makeBridge(surface: surface, sleeper: ManualSleeper(), showInAllSpaces: false)

        await bridge.expand()
        // The fake builds its window with `NookPanel`'s unconditional `.canJoinAllSpaces`,
        // so this can only hold if the bridge wrote the preference back afterwards.
        #expect(!surface.window.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(!surface.window.isOpaque)
        #expect(!surface.window.isReleasedWhenClosed)

        surface.simulateWindowRebuild()
        await bridge.compact()
        #expect(!surface.window.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(!surface.window.isOpaque)
        #expect(!surface.window.isReleasedWhenClosed)
        _ = bridge
    }

    @Test("a hidden surface reports no live window and nothing is applied")
    func chromeSkippedWithoutLiveWindow() async {
        let surface = FakeIslandSurface()
        surface.hasLiveWindow = false
        let bridge = makeBridge(surface: surface, sleeper: ManualSleeper())

        await bridge.expand()
        #expect(surface.configureWindowCallCount == 0)
    }

    /// Regression: C1 — a display change rebuilds the surface's window without any state
    /// transition, so neither `onExpand` nor `onCompact` fires and the fresh panel comes
    /// back with the vendored defaults.
    @Test("a display change does not put the island back on every Space")
    func chromeSurvivesScreenParameterChange() async throws {
        let surface = FakeIslandSurface()
        let bridge = makeBridge(surface: surface, sleeper: ManualSleeper(), showInAllSpaces: false)

        await bridge.expand()
        #expect(!surface.window.collectionBehavior.contains(.canJoinAllSpaces))

        // What the vendored surface does on `didChangeScreenParameters`: rebuild the
        // window in place, staying expanded — bringing back `NookPanel`'s unconditional
        // `.canJoinAllSpaces`, which is the user-visible symptom.
        surface.simulateWindowRebuild()
        #expect(surface.window.collectionBehavior.contains(.canJoinAllSpaces))

        NotificationCenter.default.post(
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        var restored = false
        for _ in 0..<200 {
            try await Task.sleep(for: .milliseconds(10))
            if !surface.window.collectionBehavior.contains(.canJoinAllSpaces) {
                restored = true
                break
            }
        }
        #expect(restored)
        #expect(!surface.window.isReleasedWhenClosed)
        #expect(surface.state == .expanded)
        _ = bridge
    }

    // MARK: - Chrome style and notch width

    @Test("the chrome style reaches the surface through the bridge")
    func chromeStyleReachesSurface() {
        let surface = FakeIslandSurface()
        let bridge = makeBridge(surface: surface, sleeper: ManualSleeper())

        bridge.applyChromeStyle(.floating)
        #expect(surface.appliedChromeStyles == [.floating])
    }

    @Test("switching style at runtime rebuilds the window, and chrome is restored after it")
    func chromeStyleSwitchesAtRuntime() async {
        let surface = FakeIslandSurface()
        let bridge = makeBridge(surface: surface, sleeper: ManualSleeper())

        await bridge.expand()
        bridge.applyChromeStyle(.floating)
        bridge.applyChromeStyle(.notch)

        #expect(surface.appliedChromeStyles == [.floating, .notch])
        #expect(!surface.window.isReleasedWhenClosed)
        #expect(!surface.window.isOpaque)
    }

    @Test("the synthetic notch width reaches the surface, and its rebuild keeps chrome")
    func syntheticNotchWidthReachesSurface() async {
        let surface = FakeIslandSurface()
        let bridge = makeBridge(surface: surface, sleeper: ManualSleeper())

        await bridge.expand()
        bridge.applySyntheticNotchWidth(208)

        #expect(surface.appliedSyntheticNotchWidths == [208])
        #expect(!surface.window.isReleasedWhenClosed)
    }

    // MARK: - Auto-collapse

    @Test("hover exit while expanded collapses the surface after the delay")
    func hoverExitCollapses() async {
        let surface = FakeIslandSurface()
        let sleeper = ManualSleeper()
        let bridge = makeBridge(surface: surface, sleeper: sleeper, delay: .seconds(3))

        await bridge.expand()
        surface.setHovering(true)
        surface.setHovering(false)
        await settle()

        #expect(sleeper.sleepCallCount == 1)
        #expect(sleeper.requestedDurations == [.seconds(3)])
        #expect(surface.compactCallCount == 0)

        sleeper.releaseAll()
        await settle()
        #expect(surface.compactCallCount == 1)
        #expect(surface.state == .compact)
    }

    @Test("re-entering the surface cancels the pending collapse")
    func hoverReentryCancelsCollapse() async {
        let surface = FakeIslandSurface()
        let sleeper = ManualSleeper()
        let bridge = makeBridge(surface: surface, sleeper: sleeper)

        await bridge.expand()
        surface.setHovering(true)
        surface.setHovering(false)
        surface.setHovering(true)
        await settle()

        // Releasing proves the collapse is dead rather than merely still waiting.
        sleeper.releaseAll()
        await settle()
        #expect(surface.compactCallCount == 0)
        #expect(surface.state == .expanded)
        _ = bridge
    }

    @Test("hover exit while compact schedules nothing")
    func hoverExitWhileCompactIsInert() async {
        let surface = FakeIslandSurface()
        let sleeper = ManualSleeper()
        let bridge = makeBridge(surface: surface, sleeper: sleeper)

        surface.setHovering(true)
        surface.setHovering(false)
        await settle()

        #expect(sleeper.sleepCallCount == 0)
        #expect(surface.compactCallCount == 0)
        _ = bridge
    }

    @Test("an explicit expand cancels a collapse already scheduled by a hover exit")
    func explicitExpandCancelsPendingCollapse() async {
        let surface = FakeIslandSurface()
        let sleeper = ManualSleeper()
        let bridge = makeBridge(surface: surface, sleeper: sleeper)

        await bridge.expand()
        surface.setHovering(true)
        surface.setHovering(false)
        await bridge.expand()

        sleeper.releaseAll()
        await settle()
        #expect(surface.compactCallCount == 0)
        #expect(surface.state == .expanded)
    }

    /// Regression: N1 — left at the vendored default, converting between compact and
    /// expanded dips through `.hidden`. Reporting that dip as a hide would make the host
    /// tear the island down and rebuild it on every card open — the most common gesture
    /// in the app. The bridge turns the dip off, and filters the report if it ever
    /// returns, which is what this exercises.
    @Test("an intermediate hide during a conversion is not reported as the surface hiding")
    func intermediateHideIsNotReportedAsHidden() async {
        let surface = FakeIslandSurface()
        surface.usesIntermediateHides = true
        let bridge = makeBridge(surface: surface, sleeper: ManualSleeper())
        var hiddenCount = 0
        var expandedCount = 0
        var compactedCount = 0
        bridge.onSurfaceHidden = { hiddenCount += 1 }
        bridge.onSurfaceExpanded = { expandedCount += 1 }
        bridge.onSurfaceCompacted = { compactedCount += 1 }

        await bridge.expand()
        await bridge.compact()
        await bridge.expand()
        await settle()

        #expect(hiddenCount == 0)
        #expect(expandedCount == 2)
        #expect(compactedCount == 1)
        #expect(surface.state == .expanded)
    }

    /// The other half of N1: filtering the intermediate hide must not swallow a real one.
    @Test("a terminal hide is still reported when conversions dip through hidden")
    func terminalHideIsStillReported() async {
        let surface = FakeIslandSurface()
        surface.usesIntermediateHides = true
        let bridge = makeBridge(surface: surface, sleeper: ManualSleeper())
        var hiddenCount = 0
        bridge.onSurfaceHidden = { hiddenCount += 1 }

        await bridge.expand()
        surface.simulateHide()
        await settle()

        #expect(hiddenCount == 1)
        #expect(surface.state == .hidden)
    }

    /// Regression: C2 — hiding publishes `state = .hidden` *and* `isHovering = false`. A
    /// bridge that only watched expand/compact read the hover drop as "cursor left an
    /// expanded surface", scheduled a collapse, and the resulting `compact()` rebuilt a
    /// window — the island reappeared seconds after the user dismissed it.
    @Test("hiding the surface does not resurrect it seconds later")
    func hideDoesNotScheduleAZombieCollapse() async {
        let surface = FakeIslandSurface()
        let sleeper = ManualSleeper()
        let bridge = makeBridge(surface: surface, sleeper: sleeper)
        var hiddenCount = 0
        bridge.onSurfaceHidden = { hiddenCount += 1 }

        await bridge.expand()
        surface.setHovering(true)
        surface.simulateHide()
        await settle()

        #expect(hiddenCount == 1)
        #expect(sleeper.sleepCallCount == 0)

        sleeper.releaseAll()
        await settle()
        #expect(surface.compactCallCount == 0)
        #expect(surface.state == .hidden)
    }

    /// Regression: C2, second half — even if a collapse was already in flight when the
    /// surface went away, it must not run once released.
    @Test("a collapse already waiting is abandoned when the surface hides")
    func pendingCollapseIsAbandonedOnHide() async {
        let surface = FakeIslandSurface()
        let sleeper = ManualSleeper()
        let bridge = makeBridge(surface: surface, sleeper: sleeper)

        await bridge.expand()
        surface.setHovering(true)
        surface.setHovering(false)
        await settle()
        #expect(sleeper.sleepCallCount == 1)

        surface.simulateHide()
        sleeper.releaseAll()
        await settle()

        #expect(surface.compactCallCount == 0)
        #expect(surface.state == .hidden)
        _ = bridge
    }

    /// Regression: C3 — a surface with no compact content turns `compact()` into a hide,
    /// so `onCompact` never fires. The bridge must still learn the surface is no longer
    /// expanded, and must report the outcome that actually happened.
    @Test("a compact that collapses to hidden is reported as hidden, not as compacted")
    func compactThatHidesIsReportedAsHidden() async {
        let surface = FakeIslandSurface()
        surface.compactCollapsesToHide = true
        let sleeper = ManualSleeper()
        let bridge = makeBridge(surface: surface, sleeper: sleeper)
        var compactedCount = 0
        var hiddenCount = 0
        bridge.onSurfaceCompacted = { compactedCount += 1 }
        bridge.onSurfaceHidden = { hiddenCount += 1 }

        await bridge.expand()
        await bridge.compact()
        await settle()

        #expect(compactedCount == 0)
        #expect(hiddenCount == 1)
        #expect(surface.state == .hidden)

        // And the bridge's own notion of expansion followed, so a later hover exit does
        // not schedule a collapse against a surface that is already gone.
        surface.setHovering(true)
        surface.setHovering(false)
        await settle()
        #expect(sleeper.sleepCallCount == 0)
    }
}
