import SwiftUI

struct WaveformView: View {
    let isPlaying: Bool
    var colors: [Color] = ArtworkPalette.fallback.gradientColors
    var externalLevels: [Float]? = nil

    /// Keep this false when capture is active, even if the current audio frame
    /// is silent. Silence should render as silence, not as a fake sine wave.
    var usesSyntheticFallback = false

    private let barCount = AudioSpectrumAnalyzer.bandCount
    private let barWidth: CGFloat = 2.5
    private let maxHeight: CGFloat = 18
    private let minHeight: CGFloat = 2
    private let spacing: CGFloat = 2

    var body: some View {
        Group {
            if isPlaying, externalLevels == nil, usesSyntheticFallback {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    waveform(levels: syntheticLevels(at: context.date))
                }
            } else {
                waveform(levels: liveOrIdleLevels)
            }
        }
        .frame(
            width: CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing,
            height: maxHeight
        )
        .accessibilityHidden(true)
    }

    private var liveOrIdleLevels: [Float] {
        guard isPlaying, let externalLevels else {
            return [Float](repeating: 0, count: barCount)
        }

        return (0..<barCount).map { index in
            guard index < externalLevels.count else { return 0 }
            return min(1, max(0, externalLevels[index]))
        }
    }

    private func waveform(levels: [Float]) -> some View {
        ZStack {
            LinearGradient(
                colors: colors.isEmpty ? ArtworkPalette.fallback.gradientColors : colors,
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )

            // A subtle vertical sheen adds material depth without turning the
            // tiny bars into separate per-bar gradients.
            LinearGradient(
                colors: [
                    .white.opacity(0.20),
                    .clear,
                    .black.opacity(0.18),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .blendMode(.softLight)
        }
        .mask {
            bars(levels: levels)
        }
        .compositingGroup()
    }

    private func bars(levels: [Float]) -> some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { index in
                let level = index < levels.count ? CGFloat(levels[index]) : 0
                let height = minHeight + (maxHeight - minHeight) * max(0.025, level)

                RoundedRectangle(cornerRadius: barWidth / 2, style: .continuous)
                    .fill(.white)
                    .frame(width: barWidth, height: height)
                    .animation(.easeOut(duration: 0.05), value: height)
            }
        }
        .frame(height: maxHeight)
    }

    private func syntheticLevels(at date: Date) -> [Float] {
        guard isPlaying else { return [Float](repeating: 0, count: barCount) }
        let time = date.timeIntervalSinceReferenceDate

        return (0..<barCount).map { index in
            let phase = Double(index) * 0.77
            let slow = 0.32 + 0.24 * sin(time * (1.55 + Double(index % 3) * 0.12) + phase)
            let detail = 0.15 * sin(time * (3.1 + Double(index % 4) * 0.19) + phase * 1.7)
            return Float(min(0.82, max(0.08, slow + detail)))
        }
    }
}
