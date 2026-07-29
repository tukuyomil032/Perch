import SwiftUI

/// The two compact-mode slots that straddle the notch gap.
///
/// The vendored surface lays compact content out as `[leading][notch gap][trailing]`, so
/// the single ~150pt strip Perch used to draw inside its own capsule has to be split.
/// Artwork and title go leading, the waveform goes trailing — the Dynamic Island idiom,
/// and the split that keeps every existing subview untouched.
///
/// Neither slot paints a background, a shape or a stroke. That chrome belongs to the
/// surface now (`NookShape` + `NookBackdrop`); drawing a capsule in here would render a
/// pill inside the notch shape.
struct IslandCompactLeading: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        // No music: the slot collapses to nothing and the notch shape closes up around
        // the gap on its own. An `EmptyView` would do, but a zero-size `Color.clear`
        // keeps the surface's width measurement well-defined.
        if let state = appState.nowPlayingManager.currentState {
            HStack(spacing: 6) {
                NowPlayingArtworkThumbnail(state: state)
                MarqueeText(text: compactLabel(for: state), font: .system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 120, maxHeight: 16)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        } else {
            Color.clear.frame(width: 0, height: 0)
        }
    }

    private func compactLabel(for state: NowPlayingState) -> String {
        if state.isAd { return "Spotify Ad" }
        return state.artist.isEmpty ? state.title : "\(state.title) — \(state.artist)"
    }
}

struct IslandCompactTrailing: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let state = appState.nowPlayingManager.currentState {
            let capture = appState.nowPlayingManager.audioCaptureService
            let hasLiveAudio = capture.isCaptureActive && capture.hasReceivedAudio
            NowPlayingCompactWaveform(
                state: state,
                levels: hasLiveAudio ? capture.rmsLevels : nil,
                usesSyntheticFallback: !hasLiveAudio
            )
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        } else {
            Color.clear.frame(width: 0, height: 0)
        }
    }
}
