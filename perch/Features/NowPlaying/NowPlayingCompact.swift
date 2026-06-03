// perch/Features/NowPlaying/NowPlayingCompact.swift
import Defaults
import SwiftUI

struct NowPlayingCompact: View {
    let state: NowPlayingState
    @Default(.showNowPlayingSource) private var showSource

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            artworkThumbnail
            scrollingTitle
            WaveformView(isPlaying: state.isPlaying, color: .white.opacity(0.8))
                .accessibilityLabel(state.isPlaying ? "Playing" : "Paused")
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var artworkThumbnail: some View {
        if let artwork = state.artwork {
            Image(nsImage: artwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            Image(systemName: "music.note")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 22, height: 22)
                .accessibilityLabel("No album art")
        }
    }

    private var trackLabel: String {
        var label = "\(state.title) — \(state.artist)"
        if showSource {
            label += " | \(state.source.displayName)"
        }
        return label
    }

    private var scrollingTitle: some View {
        MarqueeText(text: trackLabel, font: .system(size: 11, weight: .medium))
            .foregroundStyle(.white)
            .frame(maxWidth: 120)
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
    @State private var scrollGeneration = 0

    var body: some View {
        GeometryReader { geo in
            Text(text)
                .font(font)
                .lineLimit(1)
                .fixedSize()
                .offset(x: offset)
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
        }
    }

    private func startScrolling() {
        let overflow = contentWidth - containerWidth
        guard overflow > 8, offset == 0 else { return }
        let gen = scrollGeneration
        let duration = Double(overflow) / 25.0  // 40 → 25 px/s (slower)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard scrollGeneration == gen else { return }
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                offset = -(overflow + 4)
            }
        }
    }
}
