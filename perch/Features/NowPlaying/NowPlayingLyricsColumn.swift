import SwiftUI

/// Rich mode's center column: complex multi-line lyrics, kept alongside the artwork/
/// controls column rather than the single-line afterthought other Dynamic Island style
/// apps show. Display-only — the caller (`AtollStyleExpandedView`) owns the fetch
/// lifecycle since this column's data outlives any one `NowPlayingCard` render.
struct NowPlayingLyricsColumn: View {
    let state: NowPlayingState
    let lyrics: [LyricsLine]
    let isLoading: Bool

    var body: some View {
        Group {
            if !lyrics.isEmpty {
                TimelineView(.animation(minimumInterval: 0.2, paused: !state.isPlaying)) { ctx in
                    LyricsView(
                        lines: lyrics,
                        elapsedTime: state.liveElapsed(at: ctx.date) ?? 0,
                        fontSize: 13
                    )
                }
            } else if isLoading {
                LyricsLoadingView()
            } else {
                placeholder
            }
        }
        .animation(DesignSystem.springAnimation, value: lyrics.map(\.id))
    }

    private var placeholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "music.note")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.white.opacity(0.2))
            Text("No lyrics available")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
