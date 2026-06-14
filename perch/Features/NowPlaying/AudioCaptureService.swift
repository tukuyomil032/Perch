import Accelerate
import Foundation
import Logging
import ScreenCaptureKit

@Observable
@MainActor
final class AudioCaptureService: NSObject {
    private(set) var rmsLevels: [Float] = Array(repeating: 0, count: 8)
    nonisolated(unsafe) private var stream: SCStream?
    private var currentBundleId: String?
    private let logger = Logger(label: "com.tukuyomi032.perch.AudioCaptureService")

    // FFT constants — nonisolated(unsafe) static lets are accessible from nonisolated callbacks
    nonisolated(unsafe) private static let fftN = 1024
    nonisolated(unsafe) private static let fftSampleRate = 44100.0
    nonisolated(unsafe) private static let fftBandEdges: [Double] = [
        20, 60, 200, 500, 1200, 3000, 6000, 12000, 20000,
    ]
    nonisolated(unsafe) private static let fftHannWindow: [Float] = {
        var w = [Float](repeating: 0, count: 1024)
        for i in 0..<1024 {
            w[i] = Float(0.5 * (1.0 - cos(2.0 * .pi * Double(i) / 1023.0)))
        }
        return w
    }()

    // Audio processing state — only accessed from the serial audioQueue
    nonisolated(unsafe) private var fftAccumulator: [Float] = []
    nonisolated(unsafe) private var fftSetup: FFTSetup?

    // Serial queue prevents concurrent callback races
    private let audioQueue = DispatchQueue(
        label: "com.tukuyomi032.perch.audio", qos: .userInteractive)

    override init() {
        super.init()
        fftSetup = vDSP_create_fftsetup(
            vDSP_Length(log2(Double(Self.fftN))), FFTRadix(kFFTRadix2))
    }

    deinit {
        if let s = fftSetup { vDSP_destroy_fftsetup(s) }
    }

    func startCapturing(bundleId: String) async {
        guard bundleId != currentBundleId else { return }
        await stopCapturing()
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false)
            guard
                let app = content.applications.first(where: {
                    $0.bundleIdentifier == bundleId
                }),
                let display = content.displays.first
            else { return }
            let filter = SCContentFilter(
                display: display, including: [app], exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 44100
            config.channelCount = 2
            // Minimize video to suppress "stream output NOT found" error spam
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            stream = SCStream(filter: filter, configuration: config, delegate: nil)
            try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
            // Register video output to prevent SCStream internal "NOT found" errors
            try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: audioQueue)
            try await stream?.startCapture()
            currentBundleId = bundleId
        } catch {
            let nsError = error as NSError
            let description = String(describing: error)
            let isPermissionError =
                nsError.domain == SCStreamErrorDomain
                || description.localizedCaseInsensitiveContains("permission")
                || description.localizedCaseInsensitiveContains("denied")
                || description.localizedCaseInsensitiveContains("declined")
                || description.localizedCaseInsensitiveContains("not authorized")
            if isPermissionError {
                logger.error("ScreenCapture permission/capture failed: \(description)")
            } else {
                logger.error("Audio capture failed: \(description)")
            }
            currentBundleId = nil
            stream = nil
        }
    }

    func stopCapturing() async {
        currentBundleId = nil
        try? await stream?.stopCapture()
        stream = nil
        fftAccumulator = []
        rmsLevels = Array(repeating: 0, count: 8)
    }
}

extension AudioCaptureService: SCStreamOutput {
    nonisolated func stream(
        _ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard stream === self.stream else { return }
        guard type == .audio,
            let blockBuffer = CMSampleBufferGetDataBuffer(buffer)
        else { return }
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(
            blockBuffer, atOffset: 0, lengthAtOffsetOut: nil,
            totalLengthOut: &length, dataPointerOut: &dataPointer)
        guard let ptr = dataPointer, length >= 4 else { return }
        let floatCount = length / 4
        let floatPtr = UnsafeRawPointer(ptr).bindMemory(to: Float.self, capacity: floatCount)

        // SCStream audio is non-interleaved stereo: first floatCount/2 floats = left channel
        let frameCount = floatCount / 2
        guard frameCount > 0 else { return }
        fftAccumulator.append(
            contentsOf: UnsafeBufferPointer(start: floatPtr, count: frameCount))

        let n = Self.fftN
        guard fftAccumulator.count >= n else { return }
        let frame = Array(fftAccumulator.prefix(n))
        fftAccumulator.removeFirst(n / 4)  // 75% overlap for smooth visual response

        guard let setup = fftSetup else { return }
        let levels = Self.computeFFTBands(frame: frame, setup: setup)

        Task { @MainActor [weak self, stream] in
            guard stream === self?.stream else { return }
            // Attack/Release: fast rise (0.8), slow fall (0.25) for natural bar motion
            let previous = self?.rmsLevels ?? Array(repeating: 0, count: 8)
            let smoothed = zip(levels, previous).map { new, old -> Float in
                let alpha: Float = new > old ? 0.8 : 0.25
                return alpha * new + (1 - alpha) * old
            }
            self?.rmsLevels = smoothed
        }
    }

    nonisolated private static func computeFFTBands(frame: [Float], setup: FFTSetup) -> [Float] {
        let n = fftN
        let halfN = n / 2
        let log2n = vDSP_Length(log2(Double(n)))
        let window = fftHannWindow
        let bandEdges = fftBandEdges
        let sampleRate = fftSampleRate

        // Apply Hann window to reduce spectral leakage
        var windowed = [Float](repeating: 0, count: n)
        vDSP_vmul(frame, 1, window, 1, &windowed, 1, vDSP_Length(n))

        // Pack real signal into split complex: even-indexed → real, odd-indexed → imag
        var realPart = [Float](repeating: 0, count: halfN)
        var imagPart = [Float](repeating: 0, count: halfN)
        realPart.withUnsafeMutableBufferPointer { rBuf in
            imagPart.withUnsafeMutableBufferPointer { iBuf in
                var sc = DSPSplitComplex(realp: rBuf.baseAddress!, imagp: iBuf.baseAddress!)
                windowed.withUnsafeBytes { bytes in
                    vDSP_ctoz(
                        bytes.bindMemory(to: DSPComplex.self).baseAddress!, 1,
                        &sc, 1, vDSP_Length(halfN))
                }
                vDSP_fft_zrip(setup, &sc, 1, log2n, FFTDirection(FFT_FORWARD))
            }
        }

        // Compute amplitude spectrum |X[k]|, scaled by 2/N
        var magnitudes = [Float](repeating: 0, count: halfN)
        realPart.withUnsafeBufferPointer { rBuf in
            imagPart.withUnsafeBufferPointer { iBuf in
                magnitudes.withUnsafeMutableBufferPointer { magBuf in
                    var sc = DSPSplitComplex(
                        realp: UnsafeMutablePointer(mutating: rBuf.baseAddress!),
                        imagp: UnsafeMutablePointer(mutating: iBuf.baseAddress!))
                    vDSP_zvabs(&sc, 1, magBuf.baseAddress!, 1, vDSP_Length(halfN))
                }
            }
        }
        var scale = 2.0 / Float(n)
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(halfN))

        // Map FFT bins to 8 log-spaced frequency bands, dB scale: [-70dB, -5dB] → [0, 1]
        let binWidth = sampleRate / Double(n)
        return (0..<8).map { band in
            let lowBin = max(0, Int(bandEdges[band] / binWidth))
            let highBin = min(halfN - 1, Int(bandEdges[band + 1] / binWidth))
            guard lowBin <= highBin else { return 0 }
            let avg = magnitudes[lowBin...highBin].reduce(0, +) / Float(highBin - lowBin + 1)
            let db = 20.0 * log10(max(Double(avg), 1e-9))
            return Float(max(0.0, min(1.0, (db + 70.0) / 65.0)))
        }
    }
}
