import SwiftUI

struct WaveformView: View {
    let isPlaying: Bool
    var color: Color = .white
    var externalLevels: [Float]? = nil

    private let barCount = 8
    private let barWidth: CGFloat = 2.5
    private let maxHeight: CGFloat = 18
    private let minHeight: CGFloat = 2
    private let spacing: CGFloat = 2
    private let frequencies: [Double] = [2.3, 1.8, 3.1, 1.5, 2.7, 2.0, 3.4, 1.6]
    private let phases: [Double] = [0.0, 1.1, 2.2, 3.3, 0.5, 1.7, 2.9, 0.3]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isPlaying)) { context in
            HStack(spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    let h = barHeight(index: i, date: isPlaying ? context.date : nil)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.15), color.opacity(0.65), color],
                                startPoint: .bottom, endPoint: .top
                            )
                        )
                        .frame(width: barWidth, height: h)
                        .animation(.easeInOut(duration: 0.08), value: isPlaying)
                }
            }
        }
        .frame(width: CGFloat(barCount) * (barWidth + spacing) - spacing, height: maxHeight)
    }

    private func barHeight(index i: Int, date: Date?) -> CGFloat {
        if let levels = externalLevels, i < levels.count, isPlaying {
            return minHeight + (maxHeight - minHeight) * max(0.05, CGFloat(levels[i]))
        }
        guard let date else { return minHeight }
        let t = date.timeIntervalSince1970
        let raw = sin(t * frequencies[i] + phases[i])
        let normalized = CGFloat(raw * 0.5 + 0.5)
        return minHeight + (maxHeight - minHeight) * (0.05 + 0.90 * normalized)
    }
}
