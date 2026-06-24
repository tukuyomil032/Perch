import Foundation
import Testing

@testable import perch

@Suite("AppState", .serialized)
@MainActor
struct AppStateTests {
    @Test("expand(to:) immediately sets .expanding (intermediate state) at t=0")
    func expandSetsExpandingImmediately() {
        let appState = AppState()
        appState.expand(to: .nowPlaying)
        #expect(appState.presentation == .expanding(.nowPlaying))
        #expect(appState.isExpanded == true)  // expandsSurface is true for .expanding
        #expect(appState.activeCard == .nowPlaying)
    }

    @Test("expand(to:) reaches .expanded after ~110ms")
    func expandReachesExpandedAfterDelay() async throws {
        let appState = AppState()
        appState.expand(to: .nowPlaying)
        try await Task.sleep(for: .milliseconds(200))
        #expect(appState.presentation == .expanded(.nowPlaying))
        #expect(appState.isExpanded == true)
    }

    @Test("collapse() transitions to .collapsing and isExpanded remains true (surface stays open for close animation)")
    func collapseImmediatelyCollapsing() {
        let appState = AppState()
        appState.expand(to: .nowPlaying)
        appState.collapse()
        #expect(appState.presentation == .collapsing(.nowPlaying))
        // isExpanded follows presentation.expandsSurface, which is true for .collapsing
        // so the SwiftUI surface stays open and plays the close animation before going compact.
        #expect(appState.isExpanded == true)
    }

    @Test("collapse() reaches .compact after ~500ms")
    func collapseCompletesAfterDelay() async throws {
        let appState = AppState()
        appState.expand(to: .nowPlaying)
        appState.collapse()
        try await Task.sleep(for: .milliseconds(600))
        #expect(appState.presentation == .compact)
        #expect(appState.isExpanded == false)
        #expect(appState.activeCard == .idle)
    }

    @Test("collapse() on already-compact state is a no-op")
    func collapseOnCompactIsNoOp() {
        let appState = AppState()
        appState.collapse()
        #expect(appState.presentation == .compact)
    }

    @Test("expand() cancels a pending collapse via transitionGeneration")
    func expandCancelsPendingCollapse() async throws {
        let appState = AppState()
        appState.expand(to: .nowPlaying)
        appState.collapse()
        appState.expand(to: .nowPlaying)  // bumps transitionGeneration — collapse Task aborts
        try await Task.sleep(for: .milliseconds(600))
        #expect(appState.presentation == .expanded(.nowPlaying))
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
