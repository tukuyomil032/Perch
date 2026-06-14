// perch/Features/NowPlaying/NowPlayingCard.swift
import SwiftUI

struct NowPlayingCard: View {
    let state: NowPlayingState
    let manager: NowPlayingManager

    @State private var artworkAngle: Double = 0
    @State private var displayedArtwork: NSImage? = nil
    @State private var displayedArtworkID: UUID? = nil
    @State private var lyrics: [LyricsLine] = []
    @State private var isLyricsLoading: Bool = false
    @State private var showLyricsFullView: Bool = false
    @State private var isScrubbing: Bool = false
    @State private var scrubProgress: Double = 0

    var body: some View {
        Group {
            if showLyricsFullView {
                lyricsFullView
            } else {
                twoColumnView
            }
        }
        .task(id: state.title + state.artist) {
            guard state.source != .mrMediaRemote, !state.isAd else {
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
    }

    // MARK: - Two Column View (Pattern 1: default)

    private var twoColumnView: some View {
        ZStack(alignment: .topLeading) {
            BackgroundVisualizerView(
                isPlaying: state.isPlaying,
                color: state.artwork?.dominantColor() ?? .white
            )
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    artworkView
                    if !lyrics.isEmpty {
                        TimelineView(.animation(minimumInterval: 0.2, paused: !state.isPlaying)) { ctx in
                            LyricsView(
                                lines: lyrics,
                                elapsedTime: state.liveElapsed(at: ctx.date) ?? 0,
                                fontSize: 12
                            )
                        }
                    } else if isLyricsLoading {
                        LyricsLoadingView()
                    } else {
                        trackInfo
                    }
                }
                .frame(maxHeight: .infinity)
                HStack(spacing: 0) {
                    WaveformView(
                        isPlaying: state.isPlaying,
                        color: state.artwork?.dominantColor() ?? .white.opacity(0.8),
                        externalLevels: manager.audioCaptureService.rmsLevels.allSatisfy({ $0 == 0 })
                            ? nil : manager.audioCaptureService.rmsLevels
                    )
                    .accessibilityLabel(state.isPlaying ? "Playing" : "Paused")
                    .padding(.trailing, 6)
                    Text(state.artist.isEmpty ? state.title : "\(state.title) — \(state.artist)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    if !lyrics.isEmpty {
                        Button {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                                showLyricsFullView = true
                            }
                        } label: {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.55))
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Show lyrics")
                    }
                }
                progressSection
                controlsSection
            }
            .padding(16)
        }
    }

    // MARK: - Lyrics Full View (Pattern 2)

    private var lyricsFullView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                if let img = displayedArtwork {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(state.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer()
                controlButton(systemName: "backward.fill", action: manager.previousTrack, size: 12)
                controlButton(
                    systemName: state.isPlaying ? "pause.fill" : "play.fill",
                    action: manager.togglePlayPause, size: 14
                )
                controlButton(systemName: "forward.fill", action: manager.nextTrack, size: 12)
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                        showLyricsFullView = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close lyrics")
            }
            Divider().background(.white.opacity(0.15))
            TimelineView(.animation(minimumInterval: 0.2, paused: !state.isPlaying)) { ctx in
                LyricsView(
                    lines: lyrics,
                    elapsedTime: state.liveElapsed(at: ctx.date) ?? 0,
                    fontSize: 14
                )
            }
            .frame(maxHeight: 200)
            Divider().background(.white.opacity(0.15))
            progressSection
        }
        .padding(16)
    }

    // MARK: - Artwork

    private var artworkView: some View {
        Group {
            if let img = displayedArtwork {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel("Album art: \(state.album ?? state.title)")
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.12))
                    .frame(width: 100, height: 100)
                    .overlay {
                        Image(systemName: state.isAd ? "megaphone.fill" : "music.note")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .accessibilityLabel(state.isAd ? "Spotify Ad" : "No album art")
            }
        }
        .rotation3DEffect(.degrees(artworkAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
        .onAppear {
            displayedArtwork = state.artwork
            displayedArtworkID = state.artworkID
        }
        .onChange(of: state.isAd) { _, isAd in
            if isAd {
                displayedArtwork = nil
                displayedArtworkID = nil
            }
        }
        .onChange(of: state.artworkID) { _, newID in
            guard newID != displayedArtworkID else { return }
            Task { @MainActor in
                withAnimation(.easeIn(duration: 0.18)) { artworkAngle = 90 }
                try? await Task.sleep(for: .milliseconds(180))
                displayedArtwork = state.artwork
                displayedArtworkID = newID
                withAnimation(.easeOut(duration: 0.18)) { artworkAngle = 0 }
            }
        }
    }

    // MARK: - Track Info (fallback when no lyrics)

    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(state.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
            Text(state.artist)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                TimelineView(
                    .animation(minimumInterval: 0.1, paused: !state.isPlaying || isScrubbing)
                ) { ctx in
                    let p = isScrubbing ? scrubProgress : state.liveProgress(at: ctx.date)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.15))
                            .frame(height: isScrubbing ? 5 : 3)
                        Capsule()
                            .fill(.white.opacity(isScrubbing ? 1.0 : 0.8))
                            .frame(width: max(0, geo.size.width * p), height: isScrubbing ? 5 : 3)
                    }
                    .animation(.easeInOut(duration: 0.08), value: isScrubbing)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isScrubbing = true
                            scrubProgress = max(0, min(1, value.location.x / geo.size.width))
                        }
                        .onEnded { value in
                            let pos = max(0, min(1, value.location.x / geo.size.width))
                            if let dur = state.duration {
                                manager.seek(to: pos * dur)
                            }
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(300))
                                isScrubbing = false
                            }
                        }
                )
            }
            .frame(height: 14)

            TimelineView(.animation(minimumInterval: 1.0, paused: !state.isPlaying)) { ctx in
                HStack {
                    Text(isScrubbing ? scrubElapsedLabel : state.liveFormattedElapsed(at: ctx.date))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    if let remaining = isScrubbing
                        ? scrubRemainingLabel : state.liveRemaining(at: ctx.date)
                    {
                        Text(remaining)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                    } else {
                        Text(state.formattedDuration)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
        }
    }

    private var scrubElapsedLabel: String {
        guard let dur = state.duration else { return "-:--" }
        let s = max(0, Int(scrubProgress * dur))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private var scrubRemainingLabel: String? {
        guard let dur = state.duration else { return nil }
        let s = max(0, Int(dur - scrubProgress * dur))
        return String(format: "-%d:%02d", s / 60, s % 60)
    }

    // MARK: - Controls

    private var controlsSection: some View {
        HStack(spacing: 0) {
            Spacer()
            controlButton(systemName: "backward.fill", action: manager.previousTrack)
                .accessibilityLabel("Previous track")
            Spacer()
            controlButton(
                systemName: state.isPlaying ? "pause.fill" : "play.fill",
                action: manager.togglePlayPause,
                size: 22
            )
            .accessibilityLabel(state.isPlaying ? "Pause" : "Play")
            Spacer()
            controlButton(systemName: "forward.fill", action: manager.nextTrack)
                .accessibilityLabel("Next track")
            Spacer()
        }
    }

    private func controlButton(
        systemName: String,
        action: @escaping @MainActor () -> Void,
        size: CGFloat = 16
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct BackgroundVisualizerView: View {
    let isPlaying: Bool
    let color: Color

    private let barCount = 24
    private let frequencies: [Double] = (0..<24).map { 1.5 + Double($0 % 7) * 0.3 }
    private let phases: [Double] = (0..<24).map { Double($0) * 0.42 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { ctx in
            Canvas { context, size in
                let t = ctx.date.timeIntervalSince1970
                let barW = size.width / CGFloat(barCount)
                for i in 0..<barCount {
                    let raw = sin(t * frequencies[i] + phases[i])
                    let normalized = raw * 0.5 + 0.5
                    let h = size.height * (0.05 + 0.60 * normalized)
                    let x = barW * CGFloat(i) + barW * 0.2
                    let w = barW * 0.6
                    let rect = CGRect(x: x, y: size.height - h, width: w, height: h)
                    let path = Path(roundedRect: rect, cornerRadius: w / 2)
                    context.fill(path, with: .color(color.opacity(0.08)))
                }
            }
        }
    }
}
