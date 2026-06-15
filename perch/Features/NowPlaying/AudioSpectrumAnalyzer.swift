import Accelerate
import Foundation

/// Stateful FFT analyser intended to be called only from AudioCaptureService's
/// serial audio callback queue.
///
/// The class is marked @unchecked Sendable because the owner guarantees serial
/// access. Do not call consume/reset concurrently from arbitrary queues.
final class AudioSpectrumAnalyzer: @unchecked Sendable {
    nonisolated(unsafe) static let bandCount = 8

    nonisolated(unsafe) private let fftSize = 2_048
    nonisolated(unsafe) private let hopSize = 512
    nonisolated(unsafe) private let bandEdgesHz: [Float] = [45, 90, 180, 360, 720, 1_440, 2_880, 5_760, 12_000]
    nonisolated(unsafe) private let bandGainDB: [Float] = [0, 0.5, 1.5, 2.5, 4, 5.5, 7.5, 9.5]
    nonisolated(unsafe) private let fftSetup: FFTSetup
    nonisolated(unsafe) private let window: [Float]
    nonisolated(unsafe) private let publishInterval: TimeInterval

    nonisolated(unsafe) private var accumulator: [Float] = []
    nonisolated(unsafe) private var smoothedLevels = [Float](repeating: 0, count: 8)
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

        // Remove DC before windowing. Otherwise the first visual band can stay
        // artificially high even when no audible bass is present.
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

        // The Hann window has a coherent gain of roughly 0.5, hence 4/N.
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

        // In a packed real FFT, index 0 contains DC/Nyquist bookkeeping rather
        // than a normal audible bin. Ignore it completely.
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

            // Mean energy keeps the display stable; a small peak component
            // preserves transients such as kicks and hi-hats.
            let visualPower = 0.78 * meanPower + 0.22 * peakPower
            let db = 10 * log10(max(visualPower, 1e-12))
            return db + bandGainDB[band]
        }
    }

    nonisolated private func updateMotionFilter(with bandDB: [Float], sampleRate: Float) {
        guard bandDB.count == Self.bandCount else { return }

        let framePeak = bandDB.max() ?? -120

        // Gentle automatic gain makes quiet and loud sources occupy a similar
        // visual range without amplifying silence indefinitely.
        if framePeak > -72 {
            let desiredGain = clamp(-14 - framePeak, minimum: -8, maximum: 18)
            let coefficient: Float = desiredGain < autoGainDB ? 0.16 : 0.025
            autoGainDB += (desiredGain - autoGainDB) * coefficient
        }

        let floorDB: Float = -60
        let ceilingDB: Float = -14

        var normalized = bandDB.map { db -> Float in
            let linear = clamp(
                (db + autoGainDB - floorDB) / (ceilingDB - floorDB),
                minimum: 0,
                maximum: 1
            )

            // Expand quiet detail while retaining headroom for transients.
            let compressed = powf(linear, 0.62)
            return compressed < 0.025 ? 0 : compressed
        }

        // Small spatial blur makes eight tiny bars read as one coherent audio
        // activity instead of eight unrelated meters.
        var spatiallySmoothed = normalized
        for index in normalized.indices {
            if index == 0 {
                spatiallySmoothed[index] = 0.82 * normalized[index] + 0.18 * normalized[index + 1]
            } else if index == normalized.count - 1 {
                spatiallySmoothed[index] = 0.18 * normalized[index - 1] + 0.82 * normalized[index]
            } else {
                spatiallySmoothed[index] =
                    0.14 * normalized[index - 1]
                    + 0.72 * normalized[index]
                    + 0.14 * normalized[index + 1]
            }
        }
        normalized = spatiallySmoothed

        let frameDuration = Float(hopSize) / sampleRate
        let attack = 1 - expf(-frameDuration / 0.035)
        let release = 1 - expf(-frameDuration / 0.20)

        for index in 0..<Self.bandCount {
            let target = normalized[index]
            let coefficient = target > smoothedLevels[index] ? attack : release
            smoothedLevels[index] += (target - smoothedLevels[index]) * coefficient
            smoothedLevels[index] = clamp(smoothedLevels[index], minimum: 0, maximum: 1)
        }
    }

    nonisolated private func clamp(_ value: Float, minimum: Float, maximum: Float) -> Float {
        min(maximum, max(minimum, value))
    }
}
