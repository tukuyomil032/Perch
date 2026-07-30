import SwiftUI

/// Rich mode's Home-module layout: a now-playing activity card on the left, a calendar
/// panel on the right.
///
/// Not preset-driven like Minimal mode's `presetContent` — this is a fixed layout, so
/// there's nothing here for `PresetTabBar` to switch between (see `ExpandedIslandView`).
struct AtollStyleExpandedView: View {
    @Environment(AppState.self) private var appState
    @State private var contentVisible = false
    @State private var lyrics: [LyricsLine] = []
    @State private var isLyricsLoading = false
    @State private var leftColumnHeight: CGFloat = DesignSystem.atollColumnFallbackHeight

    private var currentState: NowPlayingState? {
        appState.nowPlayingManager.currentState
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            mainActivity
                .frame(minWidth: 260, idealWidth: 300, alignment: .leading)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { leftColumnHeight = $0 }

            if let state = currentState {
                Divider().opacity(0.08)
                NowPlayingLyricsColumn(state: state, lyrics: lyrics, isLoading: isLyricsLoading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: leftColumnHeight)
            }

            Divider().opacity(0.08)
            CalendarWidget()
                .frame(width: 200, alignment: .leading)
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

    /// Now-playing when there's music; a quiet empty state otherwise. AI Usage lives
    /// behind its own module button (`ModuleSwitcher.aiUsage` → `AIUsageFullView`) so it
    /// never appears here out of context.
    @ViewBuilder
    private var mainActivity: some View {
        if let state = currentState {
            NowPlayingCard(state: state, manager: appState.nowPlayingManager)
        } else {
            NoActivityView()
        }
    }
}

private struct NoActivityView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.white.opacity(0.25))
            VStack(spacing: 2) {
                Text("Nothing playing")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                Text("Music will show up here.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
