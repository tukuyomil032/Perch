import Foundation
import Testing

@testable import perch

@Suite("AudioSpectrumAnalyzer")
@MainActor
struct AudioSpectrumAnalyzerTests {

    @Test("Levels decay below 0.10 within ~500ms of silence")
    func releaseIsSnappyAfterSilence() {
        let sampleRate: Float = 44_100
        let analyzer = AudioSpectrumAnalyzer(publishRateHz: 0)

        // Feed in FFT-sized chunks so consume() doesn't hit its internal
        // accumulator-truncation guard (fftSize * 8) and drop hops silently.
        let chunkSize = 2_048

        // Prime ~2.8 s of broadband noise so every band's smoothed level
        // reaches a stable elevated value before silence begins.
        for chunk in 0..<60 {
            let noise = generateNoise(sampleCount: chunkSize, amplitude: 0.7, seed: UInt64(chunk + 1))
            _ = analyzer.consume(samples: noise, sampleRate: sampleRate)
        }

        // Feed ~1.1 s of silence in the same chunk size. With release times
        // ≤ 155 ms this should decay the loudest band well below 0.10 —
        // guards against anyone reverting to the sluggish 150-260 ms range.
        let silenceChunk = [Float](repeating: 0, count: chunkSize)
        var lastPeak: Float = 0
        for _ in 0..<25 {
            if let levels = analyzer.consume(samples: silenceChunk, sampleRate: sampleRate) {
                lastPeak = levels.max() ?? 0
            }
        }

        #expect(
            lastPeak < 0.10,
            "Release times ≤ 155ms should decay bars below 0.10 after ~1s silence; got peak=\(lastPeak)")
    }

    @Test("Loud broadband noise settles below the ceiling (no bar-pin)")
    func doesNotPinAtCeiling() {
        let sampleRate: Float = 44_100
        let analyzer = AudioSpectrumAnalyzer(publishRateHz: 0)
        let chunkSize = 2_048

        // Prime with several seconds of loud broadband noise so AGC fully
        // converges and every band reaches its steady-state value. With the
        // old target≡ceiling design, peak bands mathematically pinned at 1.0
        // and every bar visually stuck at maxHeight regardless of dynamics.
        var lastLevels: [Float] = []
        for chunk in 0..<120 {
            let noise = generateNoise(sampleCount: chunkSize, amplitude: 0.7, seed: UInt64(chunk + 100))
            if let levels = analyzer.consume(samples: noise, sampleRate: sampleRate) {
                lastLevels = levels
            }
        }

        let peak = lastLevels.max() ?? 0
        #expect(
            peak < 0.95,
            "AGC target below ceiling should keep steady-state peak under 0.95 to leave transient headroom; got peak=\(peak)"
        )
        #expect(
            peak > 0.60,
            "Loud broadband should still register a substantial signal, not be over-attenuated; got peak=\(peak)")
    }

    @Test("Returns bandCount channels per published frame")
    func publishesBandCountChannels() {
        let sampleRate: Float = 44_100
        let analyzer = AudioSpectrumAnalyzer(publishRateHz: 0)
        let noise = generateNoise(sampleCount: 4_096, amplitude: 0.5, seed: 42)

        let levels = analyzer.consume(samples: noise, sampleRate: sampleRate)
        #expect(levels?.count == AudioSpectrumAnalyzer.bandCount)
    }

    private func generateNoise(sampleCount: Int, amplitude: Float, seed: UInt64) -> [Float] {
        var rng = SplitMix64(seed: seed)
        return (0..<sampleCount).map { _ in
            let raw = Float(Double(rng.next()) / Double(UInt64.max)) * 2 - 1
            return raw * amplitude
        }
    }
}

private struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
