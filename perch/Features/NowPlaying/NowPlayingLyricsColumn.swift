import SwiftUI

/// Rich mode's center column: complex multi-line lyrics, kept alongside the artwork/
/// controls column rather than the single-line afterthought other Dynamic Island style
/// apps show. Display-only — the caller (`RichHomeView`) owns the fetch
/// lifecycle since this column's data outlives any one `NowPlayingCard` render.
///
/// Only ever shown while lyrics exist or are loading — `RichHomeView` falls
/// back to `TodayEventsColumn` once loading finishes with nothing found, so there's no
/// "no lyrics" state to render here.
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
            } else {
                LyricsLoadingView()
            }
        }
        .frame(maxWidth: .infinity)
        .animation(DesignSystem.springAnimation, value: lyrics.map(\.id))
    }
}
