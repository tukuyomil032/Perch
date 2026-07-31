// perch/Features/NowPlaying/NowPlayingCard.swift
import SwiftUI

/// Brand logo asset for `NowPlayingCard`'s source badge; `nil` falls back to
/// `MusicSource.symbolName` (e.g. MRMediaRemote, which has no dedicated app to brand).
private func sourceLogoAssetName(_ source: MusicSource) -> String? {
    switch source {
    case .appleMusic: "apple-music-logo"
    case .spotify: "spotify-logo"
    case .youTubeMusic: "youtube-music-logo"
    case .mrMediaRemote: nil
    }
}

struct NowPlayingCard: View {
    let state: NowPlayingState
    let manager: NowPlayingManager

    @State private var artworkAngle: Double = 0
    @State private var displayedArtwork: NSImage? = nil
    @State private var displayedArtworkID: UUID? = nil
    @State private var isScrubbing: Bool = false
    @State private var scrubProgress: Double = 0
    @State private var waveformPalette = ArtworkPalette.fallback
    @State private var sourceBadgeVisible = false

    var body: some View {
        twoColumnView
            .task(id: state.artworkID) {
                waveformPalette = state.artwork?.dynamicIslandPalette() ?? .fallback
            }
    }

    // MARK: - Two Column View

    private var twoColumnView: some View {
        ZStack(alignment: .topLeading) {
            BackgroundVisualizerView(
                isPlaying: state.isPlaying,
                color: waveformPalette.primary
            )
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    artworkView
                    trackInfo
                }
                .frame(height: 128)
                progressSection
                controlsSection
            }
            .padding(16)
        }
    }

    // MARK: - Artwork

    private var artworkView: some View {
        ZStack(alignment: .bottomTrailing) {
            // Glow: a blurred, oversized copy of the same artwork behind it, per
            // docs/macOS-Expanded-Surface-Layout-Handbook-ja.md §11.2. Hit-testing is
            // disabled so it never steals clicks meant for the artwork itself.
            artworkBody
                .scaleEffect(x: 1.3, y: 1.4)
                .rotationEffect(.degrees(92))
                .blur(radius: 40)
                .opacity(state.isPlaying ? 0.5 : 0)
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.3), value: state.isPlaying)

            artworkBody

            sourceBadge
                .offset(x: 10, y: 10)
        }
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

    private var artworkBody: some View {
        Group {
            if let img = displayedArtwork {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 128, height: 128)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .accessibilityLabel("Album art: \(state.album ?? state.title)")
            } else {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(.white.opacity(0.12))
                    .frame(width: 128, height: 128)
                    .overlay {
                        Image(systemName: state.isAd ? "megaphone.fill" : "music.note")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .accessibilityLabel(state.isAd ? "Spotify Ad" : "No album art")
            }
        }
        .rotation3DEffect(.degrees(artworkAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
    }

    /// Small badge naming where the track is playing from. Bounces in 0.3s after the
    /// card appears (handbook §11.2) so it doesn't compete with the artwork itself for
    /// attention the instant the card mounts.
    private var sourceBadge: some View {
        Group {
            if let assetName = sourceLogoAssetName(state.source) {
                Image(assetName)
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
            } else {
                Image(systemName: state.source.symbolName)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
            }
        }
        .scaleEffect(sourceBadgeVisible ? 1 : 0.6)
        .opacity(sourceBadgeVisible ? 1 : 0)
        .accessibilityLabel(state.source.displayName)
        .task(id: state.artworkID) {
            sourceBadgeVisible = false
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                sourceBadgeVisible = true
            }
        }
    }

    // MARK: - Track Info

    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(state.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(state.artist)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
            if let album = state.album, !album.isEmpty {
                Text(album)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                TimelineView(
                    .animation(minimumInterval: 0.1, paused: !state.isPlaying || isScrubbing)
                ) { ctx in
                    let p = isScrubbing ? scrubProgress : state.liveProgress(at: ctx.date)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.15))
                            .frame(height: isScrubbing ? 14 : 8)
                        Capsule()
                            .fill(.white.opacity(isScrubbing ? 1.0 : 0.8))
                            .frame(width: max(0, geo.size.width * p), height: isScrubbing ? 14 : 8)
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
        .padding(.vertical, 8)
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
        HStack(spacing: 14) {
            Spacer()
            NudgeControlButton(
                systemName: "backward.fill", action: manager.previousTrack,
                iconSize: 15, frameSize: 36, nudgeDirection: -1
            )
            .accessibilityLabel("Previous track")
            NudgeControlButton(
                systemName: state.isPlaying ? "pause.fill" : "play.fill",
                action: manager.togglePlayPause,
                iconSize: 20, frameSize: 46
            )
            .accessibilityLabel(state.isPlaying ? "Pause" : "Play")
            NudgeControlButton(
                systemName: "forward.fill", action: manager.nextTrack,
                iconSize: 15, frameSize: 36, nudgeDirection: 1
            )
            .accessibilityLabel("Next track")
            Spacer()
        }
    }
}

/// A playback control button that nudges 6pt in the direction of travel when pressed
/// (handbook §11.5: "前後移動は押した方向へ6pt Nudge") — motion tied to meaning, distinct
/// from play/pause's plain symbol replace (`nudgeDirection == 0`).
private struct NudgeControlButton: View {
    let systemName: String
    let action: @MainActor () -> Void
    var iconSize: CGFloat = 16
    var frameSize: CGFloat = 44
    var nudgeDirection: CGFloat = 0

    @State private var offset: CGFloat = 0

    var body: some View {
        Button {
            if nudgeDirection != 0 {
                withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) {
                    offset = nudgeDirection * 6
                }
                withAnimation(.spring(response: 0.25, dampingFraction: 0.6).delay(0.1)) {
                    offset = 0
                }
            }
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: frameSize, height: frameSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: offset)
    }
}

struct BackgroundVisualizerView: View {
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
