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
    private let maxHeight: CGFloat = 22
    private let minHeight: CGFloat = 1
    private let spacing: CGFloat = 2

    var body: some View {
        Group {
            if isPlaying {
                // Always run at 30 fps when playing so the 35% artistic component
                // animates continuously even when real audio levels are stable.
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    waveform(levels: blendedLevels(at: context.date))
                }
            } else {
                waveform(levels: Self.idleLevels)
            }
        }
        .frame(
            width: CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing,
            height: maxHeight
        )
        .accessibilityHidden(true)
    }

    // MARK: - Level computation

    private static let idleLevels = [Float](repeating: 0, count: AudioSpectrumAnalyzer.bandCount)

    private func blendedLevels(at date: Date) -> [Float] {
        guard isPlaying else { return Self.idleLevels }

        guard let realLevels = normalizedExternalLevels() else {
            return usesSyntheticFallback ? syntheticLevels(at: date) : Self.idleLevels
        }

        let peak = realLevels.max() ?? 0

        guard peak > 0.012 else {
            return Self.idleLevels
        }

        // Direct real-audio mapping. No synthetic flourish — Atoll-style honesty
        // so users can trust that the bars actually track what they're hearing.
        return realLevels.map { level in
            clamp(Float(pow(Double(level), 0.92)), minimum: 0, maximum: 1)
        }
    }

    private func normalizedExternalLevels() -> [Float]? {
        guard let externalLevels, !externalLevels.isEmpty else {
            return nil
        }

        if externalLevels.count == barCount {
            return externalLevels.map {
                clamp($0, minimum: 0, maximum: 1)
            }
        }

        // Nearest-neighbour resampling — sufficient because callers always supply
        // AudioSpectrumAnalyzer.bandCount elements (barCount == externalLevels.count).
        return (0..<barCount).map { index in
            let ratio = Double(index) / Double(barCount)
            let rawIndex = Int(ratio * Double(externalLevels.count))
            let sourceIndex = min(externalLevels.count - 1, rawIndex)
            return clamp(externalLevels[sourceIndex], minimum: 0, maximum: 1)
        }
    }

    // MARK: - Rendering

    private var resolvedGradientColors: [Color] {
        let source = colors.isEmpty ? ArtworkPalette.fallback.gradientColors : colors
        guard source.count >= 3 else { return ArtworkPalette.fallback.gradientColors }
        return [source[0], source[1], source[2]]
    }

    private func waveform(levels: [Float]) -> some View {
        bars(levels: levels)
    }

    private func bars(levels: [Float]) -> some View {
        let gradient = unifiedGradient(colors: resolvedGradientColors)
        return HStack(alignment: .center, spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { index in
                let level = index < levels.count ? CGFloat(levels[index]) : 0
                let height = minHeight + (maxHeight - minHeight) * max(0.01, level)

                RoundedRectangle(cornerRadius: barWidth / 2, style: .continuous)
                    .fill(gradient)
                    .frame(width: barWidth, height: height)
                    .animation(.easeOut(duration: 0.028), value: height)
            }
        }
        .frame(height: maxHeight)
    }

    /// Single top→bottom gradient shared by every bar so the whole waveform
    /// reads as one artwork-tinted shape whose height varies per band, rather
    /// than a mosaic of bars each running its own color direction.
    private func unifiedGradient(colors: [Color]) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: colors[0], location: 0.0),
                .init(color: colors[1], location: 0.5),
                .init(color: colors[2], location: 1.0),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    // MARK: - Synthetic fallback

    // Higher, fully-irrational frequencies (√6, π, √3, e, √15, √(3.73)) per bar.
    private let barFreqs: [Double] = [2.414, 3.146, 1.732, 2.718, 3.873, 1.931]
    private let barPhases: [Double] = [0.000, 1.173, 2.427, 0.893, 1.972, 3.217]

    private func clamp(_ value: Float, minimum: Float, maximum: Float) -> Float {
        min(maximum, max(minimum, value))
    }

    private func syntheticLevels(at date: Date) -> [Float] {
        guard isPlaying else { return [Float](repeating: 0, count: barCount) }
        let t = date.timeIntervalSinceReferenceDate
        return (0..<barCount).map { i in
            let f = barFreqs[i]
            let p = barPhases[i]
            let a1 = 0.30 * sin(t * f + p)
            let a2 = 0.14 * sin(t * f * 1.618 + p * 0.713)
            // Rectified sine → peaks only, flat valleys = organic pulse feel
            let spike = 0.12 * max(0, sin(t * f * 5.83 + p * 2.71))
            // Slow shared breath (period ≈17 s) ties bars loosely together
            let breath = 0.04 * sin(t * 0.371 + Double(i) * 0.524)
            return Float(min(0.90, max(0.05, 0.50 + a1 + a2 + spike + breath)))
        }
    }
}
