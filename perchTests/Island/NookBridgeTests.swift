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

@Suite("NookBridge")
@MainActor
struct NookBridgeTests {

    /// Builds a bridge whose collapse timing is fully under the test's control.
    private func makeBridge(
        surface: FakeIslandSurface,
        sleeper: ManualSleeper,
        delay: Duration = .seconds(3)
    ) -> NookBridge {
        NookBridge(
            surface: surface,
            collapseDelay: { delay },
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

    @Test("the bridge takes over collapse timing from the surface")
    func bridgeOwnsCollapseTiming() {
        let surface = FakeIslandSurface()
        _ = makeBridge(surface: surface, sleeper: ManualSleeper())
        #expect(surface.staysExpandedOnHoverExit)
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

    @Test("chrome is restored after every window rebuild, not merely re-issued")
    func chromeIsReappliedOnEveryTransition() async {
        let surface = FakeIslandSurface()
        let bridge = makeBridge(surface: surface, sleeper: ManualSleeper())

        await bridge.expand()
        // The fake resets the window to `NookPanel`'s defaults as it builds it, so these
        // values can only hold if the bridge wrote them back afterwards.
        #expect(!surface.window.isOpaque)
        #expect(!surface.window.isReleasedWhenClosed)
        #expect(surface.window.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(surface.window.collectionBehavior.contains(.stationary))
        #expect(surface.window.collectionBehavior.contains(.ignoresCycle))

        surface.simulateWindowRebuild()
        await bridge.compact()
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
    @Test("a display change restores window chrome even though no transition fires")
    func chromeSurvivesScreenParameterChange() async throws {
        let surface = FakeIslandSurface()
        let bridge = makeBridge(surface: surface, sleeper: ManualSleeper())

        await bridge.expand()
        #expect(!surface.window.isReleasedWhenClosed)

        // What the vendored surface does on `didChangeScreenParameters`: rebuild the
        // window in place, staying expanded.
        surface.simulateWindowRebuild()
        #expect(surface.window.isReleasedWhenClosed)

        NotificationCenter.default.post(
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        var restored = false
        for _ in 0..<200 {
            try await Task.sleep(for: .milliseconds(10))
            if !surface.window.isReleasedWhenClosed {
                restored = true
                break
            }
        }
        #expect(restored)
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
