import SwiftUI

/// Rich mode's Home-module layout: two columns whose content swaps based on whether
/// music is playing.
///
/// Not preset-driven like Minimal mode's `presetContent` — this is a fixed layout, so
/// there's nothing here for `PresetTabBar` to switch between (see `ExpandedIslandView`).
struct AtollStyleExpandedView: View {
    @Environment(AppState.self) private var appState
    @State private var contentVisible = false
    @State private var lyrics: [LyricsLine] = []
    @State private var isLyricsLoading = false
    @State private var leftColumnHeight: CGFloat = DesignSystem.atollColumnFallbackHeight
    @State private var calendarStore = CalendarStore()

    private var currentState: NowPlayingState? {
        appState.nowPlayingManager.currentState
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            leftColumn
                .frame(minWidth: 260, idealWidth: 300, alignment: .leading)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { leftColumnHeight = $0 }

            Divider().opacity(0.08)

            centerColumn
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: leftColumnHeight)
        }
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
        guard let state = currentState, state.source != .mrMediaRemote, !state.isAd else {
            lyrics = []
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

    /// Now-playing when there's music; the calendar's month view otherwise.
    @ViewBuilder
    private var leftColumn: some View {
        if let state = currentState {
            NowPlayingCard(state: state, manager: appState.nowPlayingManager)
        } else {
            CalendarMonthColumn(store: calendarStore)
        }
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
