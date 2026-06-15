import Accelerate
import Foundation

/// Stateful FFT analyser intended to be called only from AudioCaptureService's
/// serial audio callback queue.
///
/// The class is marked @unchecked Sendable because the owner guarantees serial
/// access. Do not call consume/reset concurrently from arbitrary queues.
final class AudioSpectrumAnalyzer: @unchecked Sendable {
    nonisolated(unsafe) static let bandCount = 6

    nonisolated(unsafe) private let fftSize = 2_048
    nonisolated(unsafe) private let hopSize = 512

    // Six broad bands covering the full audible range.
    nonisolated(unsafe) private let bandEdgesHz: [Float] = [55, 130, 300, 700, 1_600, 4_000, 12_000]

    // Gentle high-shelf gain to compensate for natural low-frequency dominance.
    nonisolated(unsafe) private let bandGainDB: [Float] = [0, 1.0, 2.0, 3.5, 5.0, 7.0]

    // Per-bar attack/release times (seconds) give each bar independent inertia.
    nonisolated(unsafe) private let attackTimes: [Float] = [0.030, 0.045, 0.024, 0.038, 0.027, 0.050]
    nonisolated(unsafe) private let releaseTimes: [Float] = [0.170, 0.230, 0.150, 0.210, 0.180, 0.260]

    nonisolated(unsafe) private let fftSetup: FFTSetup
    nonisolated(unsafe) private let window: [Float]
    nonisolated(unsafe) private let publishInterval: TimeInterval

    nonisolated(unsafe) private var accumulator: [Float] = []
    nonisolated(unsafe) private var smoothedLevels = [Float](repeating: 0, count: 6)
    nonisolated(unsafe) private var autoGainDB: Float = 0
    nonisolated(unsafe) private var lastPublishedAt: TimeInterval = 0
    nonisolated(unsafe) private var currentSampleRate: Float = 44_100

    init(publishRateHz: Double = 30) {
        let log2n = vDSP_Length(log2(Double(fftSize)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            preconditionFailure("Could not create vDSP FFT setup")
        }
        fftSetup = setup
        publishInterval = publishRateHz > 0 ? 1 / publishRateHz : 0

        let n = 2_048
        window = (0..<n).map { i in
            Float(0.5 * (1 - cos(2 * Double.pi * Double(i) / Double(n - 1))))
        }
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    /// Consumes mono Float32 PCM and returns a new visual frame at most
    /// `publishRateHz` times per second.
    nonisolated func consume(samples: [Float], sampleRate: Float) -> [Float]? {
        guard !samples.isEmpty, sampleRate > 0 else { return nil }

        if abs(currentSampleRate - sampleRate) > 1 {
            currentSampleRate = sampleRate
            accumulator.removeAll(keepingCapacity: true)
        }

        accumulator.append(contentsOf: samples)

        // Avoid unbounded growth if a callback delivers a very large chunk.
        let maximumBufferedSamples = fftSize * 8
        if accumulator.count > maximumBufferedSamples {
            accumulator.removeFirst(accumulator.count - fftSize * 2)
        }

        var analysedAtLeastOneFrame = false

        while accumulator.count >= fftSize {
            let frame = Array(accumulator.prefix(fftSize))
            accumulator.removeFirst(hopSize)

            let bandDB = analyseDB(frame: frame, sampleRate: sampleRate)
            updateMotionFilter(with: bandDB, sampleRate: sampleRate)
            analysedAtLeastOneFrame = true
        }

        guard analysedAtLeastOneFrame else { return nil }

        let now = ProcessInfo.processInfo.systemUptime
        guard publishInterval == 0 || now - lastPublishedAt >= publishInterval else {
            return nil
        }
        lastPublishedAt = now
        return smoothedLevels
    }

    nonisolated func reset() {
        accumulator.removeAll(keepingCapacity: true)
        smoothedLevels = [Float](repeating: 0, count: Self.bandCount)
        autoGainDB = 0
        lastPublishedAt = 0
    }

    nonisolated private func analyseDB(frame: [Float], sampleRate: Float) -> [Float] {
        let halfSize = fftSize / 2
        let log2n = vDSP_Length(log2(Double(fftSize)))

        // Remove DC before windowing.
        var centred = frame
        var mean: Float = 0
        vDSP_meanv(centred, 1, &mean, vDSP_Length(fftSize))
        var negativeMean = -mean
        vDSP_vsadd(centred, 1, &negativeMean, &centred, 1, vDSP_Length(fftSize))

        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(centred, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        var real = [Float](repeating: 0, count: halfSize)
        var imaginary = [Float](repeating: 0, count: halfSize)

        real.withUnsafeMutableBufferPointer { realBuffer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                var split = DSPSplitComplex(
                    realp: realBuffer.baseAddress!,
                    imagp: imaginaryBuffer.baseAddress!
                )

                windowed.withUnsafeBytes { rawBuffer in
                    let complex = rawBuffer.bindMemory(to: DSPComplex.self)
                    guard let baseAddress = complex.baseAddress else { return }
                    vDSP_ctoz(baseAddress, 1, &split, 1, vDSP_Length(halfSize))
                }

                vDSP_fft_zrip(
                    fftSetup,
                    &split,
                    1,
                    log2n,
                    FFTDirection(FFT_FORWARD)
                )
            }
        }

        var amplitudeScale = 4 / Float(fftSize)
        vDSP_vsmul(real, 1, &amplitudeScale, &real, 1, vDSP_Length(halfSize))
        vDSP_vsmul(imaginary, 1, &amplitudeScale, &imaginary, 1, vDSP_Length(halfSize))

        var power = [Float](repeating: 0, count: halfSize)
        real.withUnsafeMutableBufferPointer { realBuffer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                var split = DSPSplitComplex(
                    realp: realBuffer.baseAddress!,
                    imagp: imaginaryBuffer.baseAddress!
                )
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(halfSize))
            }
        }

        power[0] = 0

        let binWidth = sampleRate / Float(fftSize)

        return (0..<Self.bandCount).map { band in
            let lowBin = max(1, Int(ceil(bandEdgesHz[band] / binWidth)))
            let highBin = min(
                halfSize - 1,
                Int(floor(bandEdgesHz[band + 1] / binWidth))
            )

            guard lowBin <= highBin else { return -120 }

            let slice = power[lowBin...highBin]
            let meanPower = slice.reduce(0, +) / Float(slice.count)
            let peakPower = slice.max() ?? 0

            let visualPower = 0.78 * meanPower + 0.22 * peakPower
            let db = 10 * log10(max(visualPower, 1e-12))
            return db + bandGainDB[band]
        }
    }

    nonisolated private func updateMotionFilter(with bandDB: [Float], sampleRate: Float) {
        guard bandDB.count == Self.bandCount else { return }

        let framePeak = bandDB.max() ?? -120

        if framePeak > -72 {
            let desiredGain = clamp(-14 - framePeak, minimum: -8, maximum: 18)
            let coefficient: Float = desiredGain < autoGainDB ? 0.16 : 0.025
            autoGainDB += (desiredGain - autoGainDB) * coefficient
        }

        let floorDB: Float = -60
        let ceilingDB: Float = -14

        // Restrained normalization: power 0.88 prevents quiet bands from
        // looking artificially tall. Noise gate at 0.10 restores true silence.
        var normalized = bandDB.map { db -> Float in
            let linear = clamp(
                (db + autoGainDB - floorDB) / (ceilingDB - floorDB),
                minimum: 0,
                maximum: 1
            )
            let shaped = powf(linear, 0.88)
            guard shaped > 0.10 else { return 0 }
            return min(1, (shaped - 0.10) / 0.90)
        }

        // Remap frequency channels to a more Dynamic Island-like visual pattern.
        // Mixes neighboring bands so the visual relationship doesn't follow a
        // strict left=bass, right=treble spectrum slope.
        let remapped = remapForDynamicIsland(normalized)

        // Light spatial smoothing (0.04/0.92/0.04) preserves bar independence.
        // The previous 0.14/0.72/0.14 blended bars too strongly together.
        normalized = applySpatialSmoothing(remapped)

        let frameDuration = Float(hopSize) / sampleRate

        // Per-bar attack/release prevents all bars sharing the same inertia.
        for index in 0..<Self.bandCount {
            let target = normalized[index]
            let attack = 1 - expf(-frameDuration / attackTimes[index])
            let release = 1 - expf(-frameDuration / releaseTimes[index])
            let coefficient = target > smoothedLevels[index] ? attack : release
            smoothedLevels[index] += (target - smoothedLevels[index]) * coefficient
            smoothedLevels[index] = clamp(smoothedLevels[index], minimum: 0, maximum: 1)
        }
    }

    /// Remaps the six frequency-ordered bands into a visual channel order that
    /// resembles the iOS Dynamic Island rather than a left-to-right spectrum slope.
    /// Bass energy (s[0]) is spread across all six bars rather than concentrated
    /// on bars 0–1, which previously caused persistent left-side dominance in
    /// bass-heavy genres (hip-hop, trap, etc.).
    nonisolated private func remapForDynamicIsland(_ s: [Float]) -> [Float] {
        guard s.count >= 6 else { return s }
        return [
            s[0] * 0.40 + s[5] * 0.40 + s[2] * 0.20,  // bar0: bass+treble+mid
            s[1] * 0.55 + s[4] * 0.45,  // bar1: low-mid+high
            s[0] * 0.30 + s[2] * 0.50 + s[4] * 0.20,  // bar2: mid-dominated
            s[1] * 0.25 + s[3] * 0.50 + s[5] * 0.25,  // bar3: mid-high
            s[0] * 0.40 + s[4] * 0.35 + s[3] * 0.25,  // bar4: bass+high+mid
            s[5] * 0.40 + s[2] * 0.35 + s[3] * 0.25,  // bar5: treble+mid
        ]
    }

    nonisolated private func applySpatialSmoothing(_ input: [Float]) -> [Float] {
        guard input.count >= 2 else { return input }
        return input.indices.map { index in
            if index == 0 {
                return input[index] * 0.94 + input[index + 1] * 0.06
            } else if index == input.count - 1 {
                return input[index - 1] * 0.06 + input[index] * 0.94
            } else {
                return input[index - 1] * 0.04 + input[index] * 0.92 + input[index + 1] * 0.04
            }
        }
    }

    nonisolated private func clamp(_ value: Float, minimum: Float, maximum: Float) -> Float {
        min(maximum, max(minimum, value))
    }
}
