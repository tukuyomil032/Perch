import Foundation
import Testing

@testable import perch

@Suite("AppState", .serialized)
@MainActor
struct AppStateTests {
    @Test("expand(to:) immediately sets .expanded without delay")
    func expandSetsExpandedImmediately() {
        let appState = AppState()
        appState.expand(to: .nowPlaying)
        #expect(appState.presentation == .expanded(.nowPlaying))
        #expect(appState.isExpanded == true)
        #expect(appState.activeCard == .nowPlaying)
    }

    @Test("collapse() immediately transitions to .collapsing while keeping surface expanded")
    func collapseImmediatelyCollapsing() {
        let appState = AppState()
        appState.expand(to: .nowPlaying)
        appState.collapse()
        #expect(appState.presentation == .collapsing(.nowPlaying))
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
}
