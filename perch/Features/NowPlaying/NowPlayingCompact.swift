import AppKit
// perch/Features/NowPlaying/NowPlayingCompact.swift
import SwiftUI

struct NowPlayingCompact: View {
    let state: NowPlayingState

    var body: some View {
        HStack(spacing: 6) {
            artworkThumbnail
            titleAndArtist
            WaveformView(isPlaying: state.isPlaying, color: .white.opacity(0.8))
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var artworkThumbnail: some View {
        if let artwork = state.artwork {
            Image(nsImage: artwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 20, height: 20)
                .clipShape(Capsule())
        } else {
            Image(systemName: "music.note")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
        }
    }

    private var titleAndArtist: some View {
        MarqueeText(text: state.title, font: .system(size: 11, weight: .medium))
            .foregroundStyle(.primary)
            .frame(maxWidth: 90)
    }
}

struct MarqueeText: View {
    let text: String
    let font: Font

    @State private var contentWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            Text(text)
                .font(font)
                .lineLimit(1)
                .fixedSize()
                .offset(x: offset)
                .background(
                    GeometryReader { textGeo in
                        Color.clear.onAppear {
                            contentWidth = textGeo.size.width
                            startScrolling(containerWidth: geo.size.width)
                        }
                    }
                )
        }
        .clipped()
        .onChange(of: text) { _, _ in
            offset = 0
            contentWidth = 0
        }
    }

    private func startScrolling(containerWidth: CGFloat) {
        let overflow = contentWidth - containerWidth
        guard overflow > 8 else { return }
        let duration = Double(overflow) / 40.0

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: true)) {
                offset = -(overflow + 4)
            }
        }
    }
}
