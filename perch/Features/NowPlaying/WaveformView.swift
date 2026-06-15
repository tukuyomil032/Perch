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
                waveform(levels: idleLevels)
            }
        }
        .frame(
            width: CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing,
            height: maxHeight
        )
        .accessibilityHidden(true)
    }

    // MARK: - Level computation

    /// Silent levels for paused state.
    private var idleLevels: [Float] {
        [Float](repeating: 0, count: barCount)
    }

    /// Blends 65% real audio with 35% artistic sine-wave motion so all bars
    /// feel alive even during sustained notes or bass-heavy sections.
    /// Falls back to 100% synthetic when audio capture is unavailable.
    private func blendedLevels(at date: Date) -> [Float] {
        let synthetic = syntheticLevels(at: date)

        if usesSyntheticFallback || externalLevels == nil {
            return synthetic
        }

        guard let ext = externalLevels else { return synthetic }

        return (0..<barCount).map { i in
            let audio = i < ext.count ? max(0, min(1, ext[i])) : 0
            return 0.65 * audio + 0.35 * synthetic[i]
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
        let gradColors = resolvedGradientColors
        return HStack(alignment: .center, spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { index in
                let level = index < levels.count ? CGFloat(levels[index]) : 0
                let height = minHeight + (maxHeight - minHeight) * max(0.01, level)

                RoundedRectangle(cornerRadius: barWidth / 2, style: .continuous)
                    .fill(gradientFill(for: index, colors: gradColors))
                    .frame(width: barWidth, height: height)
                    .animation(.easeOut(duration: 0.055), value: height)
            }
        }
        .frame(height: maxHeight)
    }

    /// Per-bar gradient: cycles through 3 patterns so not all bars share the
    /// same direction or color set — matching the iOS Dynamic Island aesthetic.
    ///
    /// - index % 3 == 0 (bars 0, 3): highlight → primary, top→bottom
    /// - index % 3 == 1 (bars 1, 4): primary fade only, top→bottom
    /// - index % 3 == 2 (bars 2, 5): primary → secondary, bottom→top
    private func gradientFill(for index: Int, colors: [Color]) -> LinearGradient {
        switch index % 3 {
        case 0:
            return LinearGradient(
                stops: [
                    .init(color: colors[0], location: 0.0),
                    .init(color: colors[1], location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom)
        case 1:
            return LinearGradient(
                stops: [
                    .init(color: colors[1], location: 0.0),
                    .init(color: colors[1].opacity(0.45), location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom)
        default:
            return LinearGradient(
                stops: [
                    .init(color: colors[1], location: 0.0),
                    .init(color: colors[2], location: 1.0),
                ],
                startPoint: .bottom, endPoint: .top)
        }
    }

    // MARK: - Synthetic fallback

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
