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
        sleeper: ManualSleeper = ManualSleeper(),
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

        // Hovering *before* expanding, because that is the only way it happens: the click
        // that opens the island puts the cursor on it. Expanding with the cursor elsewhere
        // arms auto-collapse immediately — see `expandingWithoutHoverArmsAutoCollapse`.
        surface.setHovering(true)
        await bridge.expand()
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
        await surface.simulateHide()
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

        surface.setHovering(true)
        await bridge.expand()
        await surface.simulateHide()
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

        surface.setHovering(true)
        await bridge.expand()
        surface.setHovering(false)
        await settle()
        #expect(sleeper.sleepCallCount == 1)

        await surface.simulateHide()
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

        surface.setHovering(true)
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

    // MARK: - Window-rebuild paths (A5 review: C-1 / I-2 / I-4 / M-7)

    /// Regression: C-1 — re-applying the *current* chrome style does not rebuild anything,
    /// so it cannot be used to move the island to another display. The real surface guards
    /// `presentation`'s `didSet` on `presentation != oldValue`; `FakeIslandSurface` mirrors
    /// that guard, which is what makes this test able to fail.
    ///
    /// Asserted on ``FakeIslandSurface/windowRebuildCount`` rather than on the window's
    /// chrome: `applyChromeStyle` ends in `applyWindowChrome()` either way, so a chrome
    /// assertion here would pass even against a fake that rebuilt unconditionally — i.e.
    /// against the very bug C-1 was.
    @Test("re-applying the same chrome style does not rebuild the window")
    func reapplyingSameChromeStyleIsANoOp() async {
        let surface = FakeIslandSurface()
        let bridge = makeBridge(surface: surface)
        await bridge.compact()

        bridge.applyChromeStyle(.notch)
        let rebuildsAfterFirst = surface.windowRebuildCount
        bridge.applyChromeStyle(.notch)

        #expect(surface.appliedChromeStyles == [.notch, .notch])
        #expect(surface.windowRebuildCount == rebuildsAfterFirst)
        // The window that survived is still the live one, and still carries what the bridge
        // applied to it.
        #expect(surface.window.collectionBehavior.contains(.stationary))
    }

    /// Regression: N-1 — the vendored `presentation` is a *stored* property, so a style
    /// applied while hidden is remembered even though nothing is rebuilt. This is the exact
    /// order `IslandHost` runs in: `applyInitialConfiguration()` sets the style before the
    /// `Task { await bridge.compact() }` that first shows the surface.
    @Test("a chrome style applied while hidden is remembered, so re-applying it later is still a no-op")
    func chromeStyleAppliedWhileHiddenIsRemembered() async {
        let surface = FakeIslandSurface()
        let bridge = makeBridge(surface: surface)

        bridge.applyChromeStyle(.notch)
        #expect(surface.windowRebuildCount == 0)

        await bridge.compact()
        let rebuildsAfterShowing = surface.windowRebuildCount

        bridge.applyChromeStyle(.notch)

        #expect(surface.windowRebuildCount == rebuildsAfterShowing)
    }

    /// Same shape for the pseudo-notch width, which carries the identical `didSet` guard.
    @Test("re-applying the same synthetic notch width does not rebuild the window")
    func reapplyingSameSyntheticNotchWidthIsANoOp() async {
        let surface = FakeIslandSurface()
        let bridge = makeBridge(surface: surface)
        await bridge.compact()

        bridge.applySyntheticNotchWidth(240)
        let rebuildsAfterFirst = surface.windowRebuildCount
        bridge.applySyntheticNotchWidth(240)

        #expect(surface.appliedSyntheticNotchWidths == [240, 240])
        #expect(surface.windowRebuildCount == rebuildsAfterFirst)
    }

    /// Regression: C-1 — `relocate()` is the seam that *does* rebuild unconditionally,
    /// which is what a display-preference change needs.
    @Test("relocate rebuilds the window even when nothing else changed")
    func relocateRebuildsUnconditionally() async {
        let surface = FakeIslandSurface()
        let bridge = makeBridge(surface: surface)
        await bridge.compact()
        let rebuildsBefore = surface.windowRebuildCount

        bridge.relocate()
        bridge.relocate()

        #expect(surface.relocateCallCount == 2)
        #expect(surface.windowRebuildCount == rebuildsBefore + 2)
    }

    /// Regression: C-1 — and it re-applies window chrome, because the rebuild hands back a
    /// panel carrying the vendored defaults.
    @Test("relocate re-applies window chrome to the fresh panel")
    func relocateReappliesWindowChrome() async {
        let surface = FakeIslandSurface()
        let bridge = makeBridge(surface: surface, showInAllSpaces: false)
        await bridge.compact()

        bridge.relocate()

        // `.canJoinAllSpaces` is the vendored default that a user turning the preference
        // off must not silently get back.
        #expect(!surface.window.collectionBehavior.contains(.canJoinAllSpaces))
    }

    /// Regression: I-2 — a transition that lands in the state the surface was already in
    /// still produces a new panel when the resolved screen changed, and the surface's state
    /// publisher drops the duplicate so no lifecycle callback announces it. Chrome must be
    /// re-applied anyway.
    @Test("a transition re-applies window chrome even when no callback fires")
    func transitionReappliesChromeWithoutACallback() async {
        let surface = FakeIslandSurface()
        let bridge = makeBridge(surface: surface, showInAllSpaces: false)
        await bridge.compact()

        var compactedCount = 0
        bridge.onSurfaceCompacted = { compactedCount += 1 }

        // Already compact: no state change, so no callback — but simulate the fresh panel
        // a screen change would have produced underneath.
        surface.simulateWindowRebuild()
        await bridge.compact()

        #expect(compactedCount == 0)
        #expect(!surface.window.collectionBehavior.contains(.canJoinAllSpaces))
    }

    /// Regression: I-4 — auto-collapse used to be armed only by a hover *transition*, so a
    /// surface expanded while the cursor was elsewhere never collapsed. Reachable as soon
    /// as anything other than a click on the island can expand it.
    @Test("expanding without the cursor on the surface still arms auto-collapse")
    func expandingWithoutHoverArmsAutoCollapse() async {
        let surface = FakeIslandSurface()
        let sleeper = ManualSleeper()
        let bridge = makeBridge(surface: surface, sleeper: sleeper, delay: .seconds(3))

        // No hover at any point — the cursor is somewhere else entirely.
        await bridge.expand()
        await settle()

        #expect(sleeper.sleepCallCount == 1)

        sleeper.releaseAll()
        await settle()
        #expect(surface.state == .compact)
    }

    /// Regression: I-4 — arming on expand must not fight the hover case: moving onto the
    /// surface cancels the collapse that expanding armed.
    @Test("hovering after an unhovered expand cancels the armed collapse")
    func hoverAfterUnhoveredExpandCancelsCollapse() async {
        let surface = FakeIslandSurface()
        let sleeper = ManualSleeper()
        let bridge = makeBridge(surface: surface, sleeper: sleeper)

        await bridge.expand()
        await settle()
        surface.setHovering(true)
        sleeper.releaseAll()
        await settle()

        #expect(surface.state == .expanded)
        _ = bridge
    }

    /// Regression: N-3 — the collapse re-reads the surface's live hover state after the
    /// wait, so a cursor sitting on the island keeps it open even when no hover *event*
    /// ever arrived to cancel the timer.
    ///
    /// Not redundant with `hoverAfterUnhoveredExpandCancelsCollapse`, which cancels via the
    /// publisher. The gap this closes is the cancelling *event* going missing: the collapse
    /// is armed correctly (the cursor really was elsewhere), the cursor then arrives, and
    /// SwiftUI's `.onHover` does not deliver the `true` — which it does not promise to do
    /// when a hosting view appears beneath a cursor that never moved, and which
    /// `Nook.updateHoverState`'s `guard state != .hidden` makes likelier still on the
    /// hidden → expanded path I-4 armed for.
    @Test("a collapse whose cursor is still on the island is abandoned after the wait")
    func collapseIsAbandonedWhenTheCursorIsStillOnTheSurface() async {
        let surface = FakeIslandSurface()
        let sleeper = ManualSleeper()
        let bridge = makeBridge(surface: surface, sleeper: sleeper)

        // Cursor elsewhere: expanding arms the collapse, as I-4 intends.
        await bridge.expand()
        await settle()
        #expect(sleeper.sleepCallCount == 1)

        // The cursor arrives on the island, but the hover event is dropped, so the
        // publisher-driven cancellation never runs.
        surface.suppressesHoverEvents = true
        surface.setHovering(true)

        sleeper.releaseAll()
        await settle()

        #expect(surface.state == .expanded)
        #expect(surface.compactCallCount == 0)
    }

    /// The complement: with the cursor genuinely gone, the same path still collapses. Guards
    /// against "fix" N-3 by never collapsing at all.
    @Test("a collapse whose cursor has left still runs after the wait")
    func collapseStillRunsWhenTheCursorHasLeft() async {
        let surface = FakeIslandSurface()
        let sleeper = ManualSleeper()
        let bridge = makeBridge(surface: surface, sleeper: sleeper)

        await bridge.expand()
        await settle()
        #expect(sleeper.sleepCallCount == 1)

        sleeper.releaseAll()
        await settle()

        #expect(surface.state == .compact)
    }

    /// Regression: M-7 — changing the pseudo-notch width rebuilds the window, so anything
    /// the host hung on it (the click recognizer) has to be re-applied.
    @Test("a synthetic notch width change re-applies window chrome")
    func syntheticNotchWidthChangeReappliesChrome() async {
        let surface = FakeIslandSurface()
        let bridge = makeBridge(surface: surface, showInAllSpaces: false)
        await bridge.compact()

        bridge.applySyntheticNotchWidth(240)

        #expect(!surface.window.collectionBehavior.contains(.canJoinAllSpaces))
    }

    /// Regression: I-3 / M-7 — the host's per-window setup runs on every path that produces
    /// a window, because it hangs off the chrome application the bridge already performs
    /// everywhere. This is what makes "forgot to re-attach the click target" unrepresentable.
    @Test("the host window configurator runs on every window-producing path")
    func windowConfiguratorRunsOnEveryPath() async {
        let surface = FakeIslandSurface()
        let bridge = makeBridge(surface: surface)
        var configuredCount = 0
        bridge.windowConfigurator = { _ in configuredCount += 1 }

        await bridge.compact()
        let afterCompact = configuredCount
        await bridge.expand()
        let afterExpand = configuredCount
        bridge.applyChromeStyle(.floating)
        let afterChrome = configuredCount
        bridge.applySyntheticNotchWidth(240)
        let afterWidth = configuredCount
        bridge.relocate()

        #expect(afterCompact > 0)
        #expect(afterExpand > afterCompact)
        #expect(afterChrome > afterExpand)
        #expect(afterWidth > afterChrome)
        #expect(configuredCount > afterWidth)
    }

    /// Regression: I-5 — a surface that never managed to build a window reports it, so the
    /// host can bring the island back instead of leaving the user with nothing until relaunch.
    @Test("hasLiveWindow surfaces a window the island failed to build")
    func hasLiveWindowReportsAMissingWindow() async {
        let surface = FakeIslandSurface()
        surface.hasLiveWindow = false
        let bridge = makeBridge(surface: surface)

        #expect(bridge.hasLiveWindow == false)

        surface.hasLiveWindow = true
        #expect(bridge.hasLiveWindow == true)
    }
}
