import SwiftUI

/// Rich mode's Home-module layout.
///
/// Music playing: two columns (`NowPlayingCard` left, lyrics/today's-events center).
/// No music: `CalendarStandaloneView` takes the whole row (§13's 2-pane month grid +
/// selected day's events) rather than being squeezed into the old left-column shape —
/// per docs/macOS-Expanded-Surface-Layout-Handbook-ja.md, Standalone Calendar is a
/// distinct layout from Compact Calendar, not the same column with different content.
///
/// Not preset-driven like Minimal mode's `presetContent` — this is a fixed layout, so
/// there's nothing here for `PresetTabBar` to switch between (see `ExpandedIslandView`).
struct RichHomeView: View {
    @Environment(AppState.self) private var appState
    @State private var contentVisible = false
    @State private var lyrics: [LyricsLine] = []
    @State private var isLyricsLoading = false
    @State private var calendarStore = CalendarStore()

    private var currentState: NowPlayingState? {
        appState.nowPlayingManager.currentState
    }

    var body: some View {
        Group {
            if let state = currentState {
                // `alignment: .center` (not `.top`) — centerColumn is height-locked to
                // SurfaceMetrics.lyricsColumnHeight (130pt) while NowPlayingCard's natural
                // height runs 220-260pt; top-aligning left the lyrics box pinned to the row's
                // top edge with dead space below it instead of sitting centered against the
                // taller card next to it.
                HStack(alignment: .center, spacing: 0) {
                    NowPlayingCard(state: state, manager: appState.nowPlayingManager)
                        .frame(minWidth: 260, idealWidth: 300, alignment: .leading)

                    Divider().opacity(0.08)

                    // Independent of the left column's height — see
                    // `SurfaceMetrics.lyricsColumnHeight`. The two used to be coupled
                    // (this column mirrored the left column's measured height), which
                    // is why lyrics rendered 8-9 lines instead of the intended 3-4:
                    // NowPlayingCard's own height, not a deliberate cap, was what
                    // decided how much text fit.
                    centerColumn
                        .frame(maxWidth: .infinity, alignment: .center)
                        .frame(height: SurfaceMetrics.lyricsColumnHeight)
                }
                // The vendored NookView sizes the whole expanded surface via `.fixedSize()`,
                // which lays out this subtree against an *unconstrained* (nil) proposal —
                // not just a one-time size query. Without an explicit idealWidth here, this
                // HStack's own ideal width under that nil proposal is just NowPlayingCard's
                // ideal (300pt) plus the lyrics text's natural width, typically well under
                // SurfaceMetrics.baseContentWidth (640pt); ExpandedIslandView's outer
                // `.frame(minWidth: 640)` then centers that narrower HStack as a whole block
                // inside the 640pt window, leaving centerColumn's `.frame(maxWidth: .infinity)`
                // with nothing to actually expand into. Proposing 640 explicitly here makes
                // the HStack lay out normally against a concrete width, so centerColumn
                // receives the real remaining space instead of just its content's natural size.
                .frame(idealWidth: SurfaceMetrics.baseContentWidth)
            } else {
                CalendarStandaloneView(store: calendarStore)
            }
        }
        // A floor, not a target — `NookView.expandedContent()` sizes the shell to
        // whatever this view reports (`.fixedSize()`), so content taller than this
        // still grows the shell. See `SurfaceMetrics.homeContentHeightFloor`.
        .frame(minHeight: SurfaceMetrics.homeContentHeightFloor)
        // Temporal choreography (docs/SwiftUI-Animation-Architecture-Handbook-ja.md §6):
        // content appears slightly after the shell rather than snapping in with it, so a
        // still-narrow shell never shows squashed text mid-expansion.
        .opacity(contentVisible ? 1 : 0)
        .blur(radius: contentVisible ? 0 : 18)
        .offset(y: contentVisible ? 0 : -6)
        .onAppear {
            withAnimation(.smooth(duration: 0.28).delay(0.10)) {
                contentVisible = true
            }
        }
        .task(id: lyricsTaskKey) {
            await refreshLyrics()
        }
        .task {
            await calendarStore.requestAccessAndRefresh()
        }
    }

    private var lyricsTaskKey: String {
        guard let state = currentState else { return "" }
        return state.title + state.artist
    }

    private func refreshLyrics() async {
        // Clear immediately on every re-entry (track change) so the previous track's
        // lyrics never linger on screen while the new fetch is in flight.
        lyrics = []
        guard let state = currentState, state.source != .mrMediaRemote, !state.isAd else {
            isLyricsLoading = false
            return
        }
        isLyricsLoading = true
        lyrics =
            await LyricsStore.shared.fetchLyrics(
                title: state.title,
                artist: state.artist,
                album: state.album
            ) ?? []
        isLyricsLoading = false
    }

    /// Lyrics while playing (fetched or still loading) so the column doesn't flash to
    /// today's events and back before a fetch resolves; today's events otherwise — which
    /// covers both "nothing playing" and "playing but no lyrics found".
    @ViewBuilder
    private var centerColumn: some View {
        if let state = currentState, !lyrics.isEmpty || isLyricsLoading {
            NowPlayingLyricsColumn(state: state, lyrics: lyrics, isLoading: isLyricsLoading)
        } else {
            TodayEventsColumn(store: calendarStore)
        }
    }
}
