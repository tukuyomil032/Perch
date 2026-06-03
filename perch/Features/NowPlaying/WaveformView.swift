// perch/Features/NowPlaying/WaveformView.swift
import SwiftUI

struct WaveformView: View {
    let isPlaying: Bool
    var color: Color = .white

    private let barCount = 6
    private let barWidth: CGFloat = 2.5
    private let maxHeight: CGFloat = 14
    private let minHeight: CGFloat = 2
    private let spacing: CGFloat = 2

    // Per-bar frequency and phase produce organic independent motion
    private let frequencies: [Double] = [2.1, 1.7, 2.8, 1.3, 2.4, 1.9]
    private let phases: [Double] = [0.0, 0.8, 1.6, 2.4, 3.2, 4.0]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: !isPlaying)) { context in
            HStack(spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    let h = barHeight(index: i, date: isPlaying ? context.date : nil)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color)
                        .frame(width: barWidth, height: h)
                        .animation(.easeInOut(duration: 0.15), value: isPlaying)
                }
            }
        }
        .frame(
            width: CGFloat(barCount) * (barWidth + spacing) - spacing,
            height: maxHeight
        )
    }

    private func barHeight(index i: Int, date: Date?) -> CGFloat {
        guard let date else { return minHeight }
        let t = date.timeIntervalSince1970
        let raw = sin(t * frequencies[i] + phases[i])
        let normalized = CGFloat(raw * 0.5 + 0.5)
        return minHeight + (maxHeight - minHeight) * (0.25 + 0.70 * normalized)
    }
}
