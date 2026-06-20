import SwiftUI

struct NowPlayingMorphContent: View {
    let state: NowPlayingState
    let manager: NowPlayingManager
    let isExpanded: Bool
    let showsDetails: Bool

    @State private var palette = ArtworkPalette.fallback
    @State private var isScrubbing = false
    @State private var scrubProgress = 0.0

    private var capture: AudioCaptureService {
        manager.audioCaptureService
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            compactLayer
            expandedLayer
            artwork
        }
        .task(id: state.artworkID) {
            palette = state.artwork?.dynamicIslandPalette() ?? .fallback
        }
    }

    // MARK: - Compact layer

    private var compactLayer: some View {
        HStack(spacing: 6) {
            Color.clear.frame(width: 22, height: 22)

            MarqueeText(
                text: state.artist.isEmpty
                    ? state.title
                    : "\(state.title) — \(state.artist)",
                font: .system(size: 11, weight: .medium)
            )
            .foregroundStyle(.primary)
            .frame(maxWidth: 120, maxHeight: 16)

            WaveformView(
                isPlaying: state.isPlaying,
                colors: palette.gradientColors,
                externalLevels: capture.isCaptureActive && capture.hasReceivedAudio
                    ? capture.rmsLevels
                    : nil,
                usesSyntheticFallback: !capture.isCaptureActive || !capture.hasReceivedAudio
            )
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(isExpanded ? 0 : 1)
        .blur(radius: isExpanded ? 6 : 0)
        .scaleEffect(isExpanded ? 0.985 : 1, anchor: .top)
        .allowsHitTesting(!isExpanded)
        .animation(
            isExpanded ? DesignSystem.Motion.detailOut : DesignSystem.Motion.detailIn,
            value: isExpanded
        )
    }

    // MARK: - Expanded layer

    private var expandedLayer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Color.clear.frame(width: 100, height: 100)

                VStack(alignment: .leading, spacing: 4) {
                    Text(state.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)

                    Text(state.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    WaveformView(
                        isPlaying: state.isPlaying,
                        colors: palette.gradientColors,
                        externalLevels: capture.isCaptureActive && capture.hasReceivedAudio
                            ? capture.rmsLevels
                            : nil,
                        usesSyntheticFallback: !capture.isCaptureActive || !capture.hasReceivedAudio
                    )
                }
            }
            .frame(height: 100)

            progressSection
            controlsSection
        }
        .padding(16)
        .opacity(showsDetails ? 1 : 0)
        .blur(radius: showsDetails ? 0 : 10)
        .offset(y: showsDetails ? 0 : 12)
        .allowsHitTesting(showsDetails)
        .animation(
            showsDetails ? DesignSystem.Motion.detailIn : DesignSystem.Motion.detailOut,
            value: showsDetails
        )
    }

    // MARK: - Shared artwork (single persistent view)

    @ViewBuilder
    private var artwork: some View {
        Group {
            if let image = state.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: isExpanded ? 10 : 4, style: .continuous)
                    .fill(.white.opacity(0.10))
                    .overlay {
                        Image(systemName: state.isAd ? "megaphone.fill" : "music.note")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(
            width: isExpanded ? 100 : 22,
            height: isExpanded ? 100 : 22
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: isExpanded ? 10 : 4,
                style: .continuous
            )
        )
        .offset(
            x: isExpanded ? 16 : 8,
            y: isExpanded ? 16 : 6
        )
        .animation(
            isExpanded ? DesignSystem.Motion.shellOpen : DesignSystem.Motion.shellClose,
            value: isExpanded
        )
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                TimelineView(
                    .animation(minimumInterval: 0.1, paused: !state.isPlaying || isScrubbing)
                ) { context in
                    let progress =
                        isScrubbing
                        ? scrubProgress
                        : state.liveProgress(at: context.date)

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.primary.opacity(0.14))
                            .frame(height: isScrubbing ? 5 : 3)

                        Capsule()
                            .fill(.primary.opacity(isScrubbing ? 1 : 0.82))
                            .frame(
                                width: max(0, geo.size.width * progress),
                                height: isScrubbing ? 5 : 3
                            )
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isScrubbing = true
                            scrubProgress = max(0, min(1, value.location.x / geo.size.width))
                        }
                        .onEnded { value in
                            let progress = max(0, min(1, value.location.x / geo.size.width))
                            if let duration = state.duration {
                                manager.seek(to: progress * duration)
                            }

                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(250))
                                isScrubbing = false
                            }
                        }
                )
            }
            .frame(height: 14)

            TimelineView(.animation(minimumInterval: 1, paused: !state.isPlaying)) { context in
                HStack {
                    Text(state.liveFormattedElapsed(at: context.date))
                    Spacer()
                    Text(state.liveRemaining(at: context.date) ?? state.formattedDuration)
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Controls

    private var controlsSection: some View {
        HStack(spacing: 0) {
            Spacer()
            controlButton("backward.fill", size: 16, action: manager.previousTrack)
            Spacer()
            controlButton(
                state.isPlaying ? "pause.fill" : "play.fill",
                size: 21,
                action: manager.togglePlayPause
            )
            Spacer()
            controlButton("forward.fill", size: 16, action: manager.nextTrack)
            Spacer()
        }
    }

    private func controlButton(
        _ symbol: String,
        size: CGFloat,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 44, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
