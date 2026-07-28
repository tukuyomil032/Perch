import SwiftUI

/// The two halves of the compact Now Playing strip, as standalone views.
///
/// They used to be private members of `NowPlayingCompact`, which drew artwork, title and
/// waveform as one horizontal strip inside Perch's own capsule. The vendored surface lays
/// compact content out around the notch gap instead, so the strip has to be split across
/// two slots — which means these two pieces need to be separately mountable. The drawing
/// is carried over unchanged; only the ownership moved.

/// Album artwork at compact size, with the cross-fade it has always played when the track
/// changes.
struct NowPlayingArtworkThumbnail: View {
    let state: NowPlayingState

    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0

    var body: some View {
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
        .scaleEffect(scale)
        .opacity(opacity)
        .onChange(of: state.artworkID) { _, _ in
            Task { @MainActor in
                withAnimation(.easeIn(duration: 0.12)) {
                    scale = 0.75
                    opacity = 0.0
                }
                try? await Task.sleep(for: .milliseconds(120))
                withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                    scale = 1.0
                    opacity = 1.0
                }
            }
        }
    }
}

/// The compact waveform, tinted from the current artwork.
///
/// The palette re-read after 600ms is carried over verbatim: artwork is fetched
/// asynchronously, so it is often still `nil` at the moment `artworkID` changes, and
/// without the second look the waveform would keep the fallback palette for the whole
/// track.
struct NowPlayingCompactWaveform: View {
    let state: NowPlayingState
    let levels: [Float]?
    let usesSyntheticFallback: Bool

    @State private var palette = ArtworkPalette.fallback

    var body: some View {
        WaveformView(
            isPlaying: state.isPlaying,
            colors: palette.gradientColors,
            externalLevels: levels,
            usesSyntheticFallback: usesSyntheticFallback
        )
        .accessibilityLabel(state.isPlaying ? "Playing" : "Paused")
        .task(id: state.artworkID) {
            palette = state.artwork?.dynamicIslandPalette() ?? .fallback
            if state.artwork == nil {
                try? await Task.sleep(for: .milliseconds(600))
                palette = state.artwork?.dynamicIslandPalette() ?? .fallback
            }
        }
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
