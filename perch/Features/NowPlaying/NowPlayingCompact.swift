// perch/Features/NowPlaying/NowPlayingCompact.swift
import SwiftUI

struct NowPlayingCompact: View {
    let state: NowPlayingState
    var waveformLevels: [Float]? = nil
    var usesSyntheticFallback = false

    @State private var thumbScale: CGFloat = 1.0
    @State private var thumbOpacity: Double = 1.0
    @State private var waveformPalette = ArtworkPalette.fallback

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            artworkThumbnail
            scrollingTitle
            WaveformView(
                isPlaying: state.isPlaying,
                colors: waveformPalette.gradientColors,
                externalLevels: waveformLevels,
                usesSyntheticFallback: usesSyntheticFallback
            )
            .accessibilityLabel(state.isPlaying ? "Playing" : "Paused")
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: state.artworkID) {
            waveformPalette = state.artwork?.dynamicIslandPalette() ?? .fallback
            // artwork fetch is async — if nil at artworkID change, re-check after
            // a brief window so the thumbnail updates once the fetch completes.
            if state.artwork == nil {
                try? await Task.sleep(for: .milliseconds(600))
                waveformPalette = state.artwork?.dynamicIslandPalette() ?? .fallback
            }
        }
    }

    @ViewBuilder
    private var artworkThumbnail: some View {
        Group {
            if let artwork = state.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: state.isAd ? "megaphone.fill" : "music.note")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 22, height: 22)
                    .accessibilityLabel(state.isAd ? "Spotify Ad" : "No album art")
            }
        }
        .scaleEffect(thumbScale)
        .opacity(thumbOpacity)
        .onChange(of: state.artworkID) { _, _ in
            Task { @MainActor in
                withAnimation(.easeIn(duration: 0.12)) {
                    thumbScale = 0.75
                    thumbOpacity = 0.0
                }
                try? await Task.sleep(for: .milliseconds(120))
                withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                    thumbScale = 1.0
                    thumbOpacity = 1.0
                }
            }
        }
    }

    private var trackLabel: String {
        if state.isAd { return "Spotify Ad" }
        return state.artist.isEmpty ? state.title : "\(state.title) — \(state.artist)"
    }

    private var scrollingTitle: some View {
        MarqueeText(text: trackLabel, font: .system(size: 11, weight: .medium))
            .foregroundStyle(.white)
            .frame(maxWidth: 120, maxHeight: 16)
    }
}

// MARK: - TextWidthKey PreferenceKey
private struct TextWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - MarqueeText
struct MarqueeText: View {
    let text: String
    let font: Font

    @State private var contentWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var textOpacity: Double = 1.0
    @State private var scrollGeneration = 0

    var body: some View {
        GeometryReader { geo in
            Text(text)
                .font(font)
                .lineLimit(1)
                .fixedSize()
                .offset(x: offset)
                .opacity(textOpacity)
                .background(
                    GeometryReader { textGeo in
                        Color.clear.preference(key: TextWidthKey.self, value: textGeo.size.width)
                    }
                )
                .onAppear { containerWidth = geo.size.width }
                .onChange(of: geo.size.width) { _, new in containerWidth = new }
        }
        .clipped()
        .onPreferenceChange(TextWidthKey.self) { width in
            contentWidth = width
            startScrolling()
        }
        .onChange(of: text) { _, _ in
            scrollGeneration += 1
            offset = 0
            contentWidth = 0
            textOpacity = 1.0
        }
    }

    private func startScrolling() {
        let overflow = contentWidth - containerWidth
        guard overflow > 8, offset == 0 else { return }
        scrollGeneration += 1
        let gen = scrollGeneration
        let duration = Double(overflow) / 25.0
        Task { @MainActor in
            // Initial pause before first scroll
            try? await Task.sleep(for: .seconds(1.5))
            guard scrollGeneration == gen else { return }
            while scrollGeneration == gen {
                // 1. Flow left
                withAnimation(.linear(duration: duration)) {
                    offset = -(overflow + 4)
                }
                // 2. Wait for scroll to complete
                try? await Task.sleep(for: .seconds(duration))
                guard scrollGeneration == gen else { return }
                // 3. Instantly hide + snap to center while off-screen
                textOpacity = 0
                offset = 0
                // 4. Fade in at center
                withAnimation(.easeIn(duration: 0.4)) {
                    textOpacity = 1.0
                }
                // 5. Pause 5s (includes 0.4s fade-in)
                try? await Task.sleep(for: .seconds(5.4))
                guard scrollGeneration == gen else { return }
            }
        }
    }
}
