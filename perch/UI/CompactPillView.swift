import SwiftUI

struct CompactPillView: View {
    @Environment(AppState.self) private var appState
    @State private var isHovered = false

    private var isMusicActive: Bool { appState.nowPlayingManager.currentState != nil }
    private var isIdle: Bool { !isMusicActive }
    // Frozen at the retired `PillSizePreset.medium` dimensions. This whole capsule is
    // deleted in the same phase, once the vendored surface's chrome takes over.
    private var pillW: CGFloat { 150 }
    private var pillH: CGFloat { 34 }

    var body: some View {
        singlePillView
            .scaleEffect(isHovered ? 1.012 : 1)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
            .opacity(isIdle && !isHovered ? 0.12 : 1.0)
            .animation(.easeInOut(duration: 0.25), value: isIdle)
            .animation(.easeInOut(duration: 0.25), value: isHovered)
            .contentShape(Capsule())
            .onTapGesture { handleTap() }
    }

    // MARK: - Single pill

    private var singlePillView: some View {
        pillContent
            .frame(width: pillW, height: pillH)
            .background {
                if #available(macOS 26, *) {
                    Capsule().fill(.clear).glassEffect(.regular.tint(.black), in: .capsule)
                } else {
                    Capsule().fill(Color.black)
                    VibrancyBackground()
                        .opacity(0.35)
                        .clipShape(Capsule())
                }
            }
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            }
    }

    @ViewBuilder
    private var pillContent: some View {
        Group {
            if let state = appState.nowPlayingManager.currentState {
                let capture = appState.nowPlayingManager.audioCaptureService
                NowPlayingCompact(
                    state: state,
                    waveformLevels: capture.isCaptureActive && capture.hasReceivedAudio
                        ? capture.rmsLevels
                        : nil,
                    usesSyntheticFallback: !capture.isCaptureActive || !capture.hasReceivedAudio
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(DesignSystem.springAnimation, value: isMusicActive)
    }

    // MARK: - Tap handler

    private func handleTap() {
        guard !isIdle else { return }
        appState.expand(to: .nowPlaying)
    }
}
