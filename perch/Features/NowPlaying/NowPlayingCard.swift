// perch/Features/NowPlaying/NowPlayingCard.swift
import SwiftUI

struct NowPlayingCard: View {
    let state: NowPlayingState
    var onPrevious: () -> Void
    var onPlayPause: () -> Void
    var onNext: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            artworkView
            VStack(alignment: .leading, spacing: 0) {
                trackInfo
                Spacer(minLength: 8)
                controls
                Spacer(minLength: 8)
                progressSection
            }
        }
        .padding(16)
    }

    // MARK: - Artwork

    private var artworkView: some View {
        Group {
            if let artwork = state.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.08))
                    .frame(width: 80, height: 80)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
    }

    // MARK: - Track info

    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(state.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(state.artist)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let album = state.album {
                Text(album)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Playback controls

    private var controls: some View {
        HStack(spacing: 20) {
            controlButton(systemName: "backward.fill") { onPrevious() }
            controlButton(
                systemName: state.isPlaying ? "pause.fill" : "play.fill",
                size: 18
            ) { onPlayPause() }
            controlButton(systemName: "forward.fill") { onNext() }
        }
    }

    private func controlButton(
        systemName: String,
        size: CGFloat = 14,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Progress bar

    private var progressSection: some View {
        TimelineView(.animation(minimumInterval: 1.0, paused: !state.isPlaying)) { context in
            VStack(spacing: 4) {
                progressBar(at: context.date)
                HStack {
                    Text(state.liveFormattedElapsed(at: context.date))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text(state.formattedDuration)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
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
                        .fill(.white.opacity(0.7))
                        .frame(width: geo.size.width * state.liveProgress(at: date), height: 3)
                }
            }
    }
}
