// perch/Features/NowPlaying/WaveformView.swift
import SwiftUI

/// 3本バーの再生中アニメーション。isPlaying=falseで全バーが同じ高さで静止する。
struct WaveformView: View {
    let isPlaying: Bool
    let color: Color

    @State private var heights: [CGFloat] = [0.4, 0.7, 0.5]

    private let barCount = 3
    private let barWidth: CGFloat = 2
    private let maxHeight: CGFloat = 12
    private let spacing: CGFloat = 2

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: barWidth, height: maxHeight * heights[i])
            }
        }
        .frame(height: maxHeight)
        .onAppear { updateHeights() }
        .onChange(of: isPlaying) { _, _ in updateHeights() }
    }

    private func updateHeights() {
        if isPlaying {
            for i in 0..<barCount {
                heights[i] = [0.3, 0.8, 0.5, 0.9, 0.4][i % 5]
                withAnimation(
                    .easeInOut(duration: 0.4 + Double(i) * 0.1)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.12)
                ) {
                    heights[i] = [0.9, 0.4, 1.0, 0.3, 0.8][i % 5]
                }
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                heights = [0.4, 0.4, 0.4]
            }
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        WaveformView(isPlaying: true, color: .white)
        WaveformView(isPlaying: false, color: .secondary)
    }
    .padding()
    .background(.black)
}
