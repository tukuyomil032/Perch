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
            let captureQueue = DispatchQueue.global(qos: .userInteractive)
            try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: captureQueue)
            // Register video output to prevent SCStream internal "NOT found" errors
            try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
            try await stream?.startCapture()
            currentBundleId = bundleId  // set only after successful capture start
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
        let bandSize = max(1, floatCount / 8)
        let levels: [Float] = (0..<8).map { band in
            let start = band * bandSize
            guard start < floatCount else { return 0 }
            let end = min(start + bandSize, floatCount)
            let sampleCount = end - start
            guard sampleCount > 0 else { return 0 }
            var rms: Float = 0
            vDSP_measqv(floatPtr + start, 1, &rms, vDSP_Length(sampleCount))
            // dB scale: maps [-60dB, -5dB] → [0.0, 1.0] (human hearing perception)
            let db = 20.0 * log10(max(Double(rms), 1e-7))
            return Float(max(0.0, min(1.0, (db + 60.0) / 55.0)))
        }
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
}
