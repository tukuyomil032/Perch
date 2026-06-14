import Accelerate
import Foundation
import ScreenCaptureKit

@Observable
@MainActor
final class AudioCaptureService: NSObject {
    private(set) var rmsLevels: [Float] = Array(repeating: 0, count: 8)
    private var stream: SCStream?
    private var currentBundleId: String?

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
            stream = SCStream(filter: filter, configuration: config, delegate: nil)
            try stream?.addStreamOutput(
                self, type: .audio,
                sampleHandlerQueue: .global(qos: .userInteractive))
            try await stream?.startCapture()
            currentBundleId = bundleId  // set only after successful capture start
        } catch {
            // Permission denied or app not found — pseudo-waveform fallback (no-op)
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
            return min(1.0, sqrt(rms) * 10.0)
        }
        Task { @MainActor [weak self] in self?.rmsLevels = levels }
    }
}
