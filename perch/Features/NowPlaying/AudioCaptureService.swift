import Foundation
import Logging
import ScreenCaptureKit

@Observable
@MainActor
final class AudioCaptureService: NSObject {
    /// Kept under the current name to avoid breaking all call sites. These are
    /// now frequency-band spectrum levels, not RMS values.
    private(set) var rmsLevels: [Float] = Array(
        repeating: 0,
        count: AudioSpectrumAnalyzer.bandCount
    )

    private(set) var isCaptureActive = false
    private(set) var hasReceivedAudio = false

    nonisolated(unsafe) private var stream: SCStream?
    nonisolated(unsafe) private var spectrumAnalyzer: AudioSpectrumAnalyzer

    private var currentBundleId: String?
    private let logger = Logger(label: "com.tukuyomi032.perch.AudioCaptureService")
    private let audioQueue = DispatchQueue(
        label: "com.tukuyomi032.perch.audio",
        qos: .userInteractive
    )

    override init() {
        spectrumAnalyzer = AudioSpectrumAnalyzer()
        super.init()
    }

    func startCapturing(bundleId: String) async {
        guard bundleId != currentBundleId else { return }
        await stopCapturing()

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )

            guard
                let application = content.applications.first(where: {
                    $0.bundleIdentifier == bundleId
                }),
                let display = content.displays.first
            else {
                logger.warning("Could not find capture target for bundle ID \(bundleId)")
                return
            }

            let filter = SCContentFilter(
                display: display,
                including: [application],
                exceptingWindows: []
            )

            let configuration = SCStreamConfiguration()
            configuration.capturesAudio = true
            configuration.excludesCurrentProcessAudio = true
            configuration.sampleRate = 44_100
            configuration.channelCount = 2

            // ScreenCaptureKit still expects a screen stream configuration.
            configuration.width = 2
            configuration.height = 2
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)

            let newStream = SCStream(
                filter: filter,
                configuration: configuration,
                delegate: nil
            )

            try newStream.addStreamOutput(
                self,
                type: .audio,
                sampleHandlerQueue: audioQueue
            )
            try newStream.addStreamOutput(
                self,
                type: .screen,
                sampleHandlerQueue: audioQueue
            )

            stream = newStream
            try await newStream.startCapture()

            currentBundleId = bundleId
            isCaptureActive = true
            hasReceivedAudio = false
        } catch {
            let description = String(describing: error)
            logger.error("Audio capture failed: \(description)")

            try? await stream?.stopCapture()
            stream = nil
            currentBundleId = nil
            isCaptureActive = false
            hasReceivedAudio = false
        }
    }

    func stopCapturing() async {
        currentBundleId = nil
        isCaptureActive = false
        hasReceivedAudio = false

        let previousStream = stream
        stream = nil
        try? await previousStream?.stopCapture()

        // Drain pending callbacks before resetting analyser state.
        audioQueue.sync {
            spectrumAnalyzer.reset()
        }

        rmsLevels = Array(repeating: 0, count: AudioSpectrumAnalyzer.bandCount)
    }
}

extension AudioCaptureService: SCStreamOutput {
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio, stream === self.stream else { return }

        let decoded: DecodedAudioFrame
        do {
            decoded = try AudioPCMDecoder.decodeMono(sampleBuffer)
        } catch {
            // A malformed/unsupported buffer should not kill the capture
            // session. The next valid buffer can still recover naturally.
            return
        }

        guard
            let levels = spectrumAnalyzer.consume(
                samples: decoded.monoSamples,
                sampleRate: decoded.sampleRate
            )
        else {
            return
        }

        Task { @MainActor [weak self, stream] in
            guard let self, stream === self.stream else { return }
            hasReceivedAudio = true
            rmsLevels = levels
        }
    }
}
