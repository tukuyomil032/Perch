// perch/Features/NowPlaying/NowPlayingCompactContent.swift
import SwiftUI

/// Compact pill content for NowPlaying — used by RootIslandView when collapsed.
/// Bridges NowPlayingManager.audioCaptureService into NowPlayingCompact.
struct NowPlayingCompactContent: View {
    let state: NowPlayingState
    let manager: NowPlayingManager

    var body: some View {
        let capture = manager.audioCaptureService
        NowPlayingCompact(
            state: state,
            waveformLevels: capture.isCaptureActive && capture.hasReceivedAudio
                ? capture.rmsLevels
                : nil,
            usesSyntheticFallback: !capture.isCaptureActive || !capture.hasReceivedAudio
        )
    }
}
