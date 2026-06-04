// perch/Features/NowPlaying/NowPlayingCard.swift
import SwiftUI

struct NowPlayingCard: View {
    let state: NowPlayingState
    let manager: NowPlayingManager

    @State private var artworkAngle: Double = 0
    @State private var displayedArtwork: NSImage? = nil
    @State private var displayedArtworkID: UUID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            topRow
            progressSection
            controlsSection
        }
        .padding(16)
    }

    // MARK: - Top Row

    private var topRow: some View {
        HStack(alignment: .center, spacing: 12) {
            artworkView
            trackInfo
            Spacer()
            WaveformView(
                isPlaying: state.isPlaying,
                color: state.artwork?.dominantColor() ?? .white.opacity(0.8)
            )
        }
    }

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
                        Image(systemName: "music.note")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .accessibilityLabel("No album art")
            }
        }
        .rotation3DEffect(.degrees(artworkAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
        .onAppear {
            displayedArtwork = state.artwork
            displayedArtworkID = state.artworkID
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
            if let album = state.album {
                Text(album)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        TimelineView(.animation(minimumInterval: 1.0, paused: !state.isPlaying)) { context in
            VStack(spacing: 4) {
                progressBar(at: context.date)
                timeLabels(at: context.date)
            }
        }
    }

    private func progressBar(at date: Date) -> some View {
        Capsule()
            .fill(.white.opacity(0.15))
            .frame(height: 3)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(.white.opacity(0.8))
                        .frame(width: geo.size.width * state.liveProgress(at: date), height: 3)
                }
            }
    }

    private func timeLabels(at date: Date) -> some View {
        HStack {
            Text(state.liveFormattedElapsed(at: date))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            if let remaining = state.liveRemaining(at: date) {
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
