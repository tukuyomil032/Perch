import SwiftUI

/// The two compact-mode slots that straddle the notch gap.
///
/// The vendored surface lays compact content out as `[leading][notch gap][trailing]`, so
/// the single ~150pt strip Perch used to draw inside its own capsule has to be split.
///
/// Neither slot paints a background, a shape or a stroke. That chrome belongs to the
/// surface now (`NookShape` + `NookBackdrop`); drawing a capsule in here would render a
/// pill inside the notch shape.
///
/// `IslandCompactLeading` is registry-driven: it renders whichever widget the active
/// preset names as `pillPrimary`, defaulting to `"now-playing"` for presets that don't
/// set one (both shipped presets do, via `PresetStore.injectDefaults()`). This is what
/// `PresetLayout.pillPrimary` was added for — see `docs/opennook-migration-plan.md`
/// Phase B. `IslandCompactTrailing` stays hard-coded to the now-playing waveform: it
/// reads `AudioCaptureService.rmsLevels` directly, a live audio-capture signal no
/// `PerchWidget` declares, so genericizing it has no real second widget to serve yet.
struct IslandCompactLeading: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let widgetId = appState.presetStore.activePreset?.pillPrimary ?? "now-playing"
        if let widget = appState.widgetRegistry.widget(forId: widgetId) {
            widget.body(size: .mini)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
        } else {
            // No widget registered for the id (or no music, which `NowPlayingMiniWidget`
            // itself already collapses to nothing for): keep the surface's width
            // measurement well-defined with a zero-size view rather than `EmptyView`.
            Color.clear.frame(width: 0, height: 0)
        }
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
