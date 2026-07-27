import AppKit
import Defaults
import Foundation
import Testing

@testable import perch

@Suite("NookBridge")
@MainActor
struct NookBridgeTests {

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

    @Test("the default backdrop reproduces Perch's current hudWindow vibrancy")
    func backdropVibrancy() {
        let backdrop = NookBridge.makeBackdrop(reduceTransparency: false)
        #expect(
            backdrop
                == .vibrancy(
                    NookBackdrop.Vibrancy(
                        material: .hudWindow, blendingMode: .behindWindow, darkenOpacity: 0)))
    }

    @Test("Reduce Transparency drops the visual effect view entirely")
    func backdropReduceTransparency() {
        #expect(NookBridge.makeBackdrop(reduceTransparency: true) == .solidBlack)
    }

    // MARK: - Surface driving (via the fake)

    @Test("the bridge takes over collapse timing from the surface")
    func bridgeOwnsCollapseTiming() {
        let surface = FakeIslandSurface()
        _ = NookBridge(surface: surface, collapseDelay: { .zero })
        #expect(surface.staysExpandedOnHoverExit)
    }

    @Test("expand() and compact() reach the surface and settle before returning")
    func expandAndCompactReachSurface() async {
        let surface = FakeIslandSurface()
        let bridge = NookBridge(surface: surface, collapseDelay: { .zero })

        await bridge.expand()
        #expect(surface.expandCallCount == 1)

        await bridge.compact()
        #expect(surface.compactCallCount == 1)
    }

    @Test("surface transitions are forwarded to the host callbacks")
    func transitionsAreForwarded() async {
        let surface = FakeIslandSurface()
        let bridge = NookBridge(surface: surface, collapseDelay: { .zero })
        var expandedCount = 0
        var compactedCount = 0
        bridge.onSurfaceExpanded = { expandedCount += 1 }
        bridge.onSurfaceCompacted = { compactedCount += 1 }

        await bridge.expand()
        await bridge.compact()

        #expect(expandedCount == 1)
        #expect(compactedCount == 1)
    }

    @Test("window chrome is re-applied on both transitions, because the window is rebuilt each time")
    func chromeIsReappliedOnEveryTransition() async {
        let surface = FakeIslandSurface()
        let bridge = NookBridge(surface: surface, collapseDelay: { .zero })

        await bridge.expand()
        #expect(surface.configureWindowCallCount == 1)

        await bridge.compact()
        #expect(surface.configureWindowCallCount == 2)

        // The `.canJoinAllSpaces` bit depends on the user preference, so only the
        // non-negotiable overlay baseline is asserted here; the preference mapping itself
        // is covered by the `desiredCollectionBehavior` tests above.
        #expect(surface.window.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(surface.window.collectionBehavior.contains(.stationary))
        #expect(surface.window.collectionBehavior.contains(.ignoresCycle))
    }

    @Test("a hidden surface reports no live window and nothing is applied")
    func chromeSkippedWithoutLiveWindow() async {
        let surface = FakeIslandSurface()
        surface.hasLiveWindow = false
        let bridge = NookBridge(surface: surface, collapseDelay: { .zero })

        await bridge.expand()
        #expect(surface.configureWindowCallCount == 0)
    }

    // MARK: - Chrome style

    @Test("the chrome style reaches the surface through the bridge")
    func chromeStyleReachesSurface() {
        let surface = FakeIslandSurface()
        let bridge = NookBridge(surface: surface, collapseDelay: { .zero })

        bridge.applyChromeStyle(.floating)
        #expect(surface.appliedChromeStyles == [.floating])
    }

    @Test("the style can be switched while the surface is live, and chrome is re-applied after the rebuild")
    func chromeStyleSwitchesAtRuntime() async {
        let surface = FakeIslandSurface()
        let bridge = NookBridge(surface: surface, collapseDelay: { .zero })

        await bridge.expand()
        let chromeCallsAfterExpand = surface.configureWindowCallCount

        bridge.applyChromeStyle(.floating)
        bridge.applyChromeStyle(.notch)

        #expect(surface.appliedChromeStyles == [.floating, .notch])
        // The surface rebuilds its window on a presentation change, so the collection
        // behavior has to be re-applied once per switch.
        #expect(surface.configureWindowCallCount == chromeCallsAfterExpand + 2)
    }

    // MARK: - Auto-collapse

    @Test("hover exit while expanded collapses the surface after the delay")
    func hoverExitCollapses() async throws {
        let surface = FakeIslandSurface()
        let bridge = NookBridge(surface: surface, collapseDelay: { .milliseconds(20) })

        await bridge.expand()
        surface.setHovering(true)
        surface.setHovering(false)

        try await Task.sleep(for: .milliseconds(120))
        #expect(surface.compactCallCount == 1)
        _ = bridge
    }

    @Test("re-entering the surface cancels the pending collapse")
    func hoverReentryCancelsCollapse() async throws {
        let surface = FakeIslandSurface()
        let bridge = NookBridge(surface: surface, collapseDelay: { .milliseconds(60) })

        await bridge.expand()
        surface.setHovering(true)
        surface.setHovering(false)
        surface.setHovering(true)

        try await Task.sleep(for: .milliseconds(160))
        #expect(surface.compactCallCount == 0)
        _ = bridge
    }

    @Test("hover exit while compact schedules nothing")
    func hoverExitWhileCompactIsInert() async throws {
        let surface = FakeIslandSurface()
        let bridge = NookBridge(surface: surface, collapseDelay: { .milliseconds(20) })

        surface.setHovering(true)
        surface.setHovering(false)

        try await Task.sleep(for: .milliseconds(120))
        #expect(surface.compactCallCount == 0)
        _ = bridge
    }

    @Test("an explicit expand cancels a collapse already scheduled by a hover exit")
    func explicitExpandCancelsPendingCollapse() async throws {
        let surface = FakeIslandSurface()
        let bridge = NookBridge(surface: surface, collapseDelay: { .milliseconds(60) })

        await bridge.expand()
        surface.setHovering(true)
        surface.setHovering(false)
        await bridge.expand()

        try await Task.sleep(for: .milliseconds(160))
        #expect(surface.compactCallCount == 0)
        #expect(surface.expandCallCount == 2)
    }
}
