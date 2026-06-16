import Accelerate
import AudioToolbox
import CoreMedia
import Foundation

struct DecodedAudioFrame: Sendable {
    let monoSamples: [Float]
    let sampleRate: Float
}

enum AudioPCMDecodeError: Error, LocalizedError, Sendable {
    case missingFormatDescription
    case unsupportedFormat(String)
    case emptySampleBuffer
    case audioBufferList(OSStatus)
    case missingAudioData

    var errorDescription: String? {
        switch self {
        case .missingFormatDescription:
            return "The audio sample buffer has no format description."
        case .unsupportedFormat(let description):
            return "Unsupported PCM format: \(description)"
        case .emptySampleBuffer:
            return "The audio sample buffer contains no frames."
        case .audioBufferList(let status):
            return "Could not read AudioBufferList (OSStatus \(status))."
        case .missingAudioData:
            return "The AudioBufferList contains no readable PCM data."
        }
    }
}

enum AudioPCMDecoder {
    /// Converts a CMSampleBuffer containing linear PCM into mono Float32 samples.
    ///
    /// This deliberately does not assume that ScreenCaptureKit always returns
    /// Float32, interleaved, or non-interleaved audio. The actual ASBD and
    /// AudioBufferList layout are inspected for every buffer.
    nonisolated static func decodeMono(_ sampleBuffer: CMSampleBuffer) throws -> DecodedAudioFrame {
        guard
            let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
            let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else {
            throw AudioPCMDecodeError.missingFormatDescription
        }

        let asbd = asbdPointer.pointee
        guard asbd.mFormatID == kAudioFormatLinearPCM else {
            throw AudioPCMDecodeError.unsupportedFormat(
                "formatID=\(asbd.mFormatID), expected Linear PCM"
            )
        }

        let frameCount = Int(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0 else {
            throw AudioPCMDecodeError.emptySampleBuffer
        }

        let formatFlags = asbd.mFormatFlags
        let isBigEndian = (formatFlags & kAudioFormatFlagIsBigEndian) != 0
        guard !isBigEndian else {
            throw AudioPCMDecodeError.unsupportedFormat("big-endian PCM")
        }

        let channelCount = max(1, Int(asbd.mChannelsPerFrame))
        let isNonInterleaved = (formatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let expectedBufferCount = isNonInterleaved ? channelCount : 1

        // AudioBufferList already includes storage for one AudioBuffer.
        let audioBufferListSize =
            MemoryLayout<AudioBufferList>.size
            + max(0, expectedBufferCount - 1) * MemoryLayout<AudioBuffer>.stride

        let rawPointer = UnsafeMutableRawPointer.allocate(
            byteCount: audioBufferListSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawPointer.deallocate() }

        rawPointer.initializeMemory(as: UInt8.self, repeating: 0, count: audioBufferListSize)
        let audioBufferList = rawPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        var retainedBlockBuffer: CMBlockBuffer?

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferList,
            bufferListSize: audioBufferListSize,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &retainedBlockBuffer
        )

        guard status == noErr else {
            throw AudioPCMDecodeError.audioBufferList(status)
        }

        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        var mono = [Float](repeating: 0, count: frameCount)
        var accumulatedChannelCount = 0

        let isFloat = (formatFlags & kAudioFormatFlagIsFloat) != 0
        let isSignedInteger = (formatFlags & kAudioFormatFlagIsSignedInteger) != 0
        let bitsPerChannel = Int(asbd.mBitsPerChannel)

        for buffer in buffers {
            guard let data = buffer.mData else { continue }

            // A non-interleaved AudioBuffer normally has one channel. An
            // interleaved buffer normally has all channels. Reading
            // mNumberChannels makes this work for either layout.
            let channelsInBuffer = max(1, Int(buffer.mNumberChannels))
            let requiredSampleCount = frameCount * channelsInBuffer

            if isFloat, bitsPerChannel == 32 {
                let available = Int(buffer.mDataByteSize) / MemoryLayout<Float>.stride
                guard available >= requiredSampleCount else { continue }
                let samples = data.assumingMemoryBound(to: Float.self)
                accumulate(
                    samples: samples,
                    frameCount: frameCount,
                    channelsInBuffer: channelsInBuffer,
                    scale: 1,
                    into: &mono
                )
                accumulatedChannelCount += channelsInBuffer
            } else if isFloat, bitsPerChannel == 64 {
                let available = Int(buffer.mDataByteSize) / MemoryLayout<Double>.stride
                guard available >= requiredSampleCount else { continue }
                let samples = data.assumingMemoryBound(to: Double.self)
                for frame in 0..<frameCount {
                    let base = frame * channelsInBuffer
                    for channel in 0..<channelsInBuffer {
                        mono[frame] += Float(samples[base + channel])
                    }
                }
                accumulatedChannelCount += channelsInBuffer
            } else if isSignedInteger, bitsPerChannel == 16 {
                let available = Int(buffer.mDataByteSize) / MemoryLayout<Int16>.stride
                guard available >= requiredSampleCount else { continue }
                let samples = data.assumingMemoryBound(to: Int16.self)
                for frame in 0..<frameCount {
                    let base = frame * channelsInBuffer
                    for channel in 0..<channelsInBuffer {
                        mono[frame] += Float(samples[base + channel]) / 32_768
                    }
                }
                accumulatedChannelCount += channelsInBuffer
            } else if isSignedInteger, bitsPerChannel == 32 {
                let available = Int(buffer.mDataByteSize) / MemoryLayout<Int32>.stride
                guard available >= requiredSampleCount else { continue }
                let samples = data.assumingMemoryBound(to: Int32.self)
                for frame in 0..<frameCount {
                    let base = frame * channelsInBuffer
                    for channel in 0..<channelsInBuffer {
                        mono[frame] += Float(samples[base + channel]) / 2_147_483_648
                    }
                }
                accumulatedChannelCount += channelsInBuffer
            } else {
                throw AudioPCMDecodeError.unsupportedFormat(
                    "flags=\(formatFlags), bits=\(bitsPerChannel), channels=\(channelCount)"
                )
            }
        }

        guard accumulatedChannelCount > 0 else {
            throw AudioPCMDecodeError.missingAudioData
        }

        var divisor = Float(accumulatedChannelCount)
        vDSP_vsdiv(mono, 1, &divisor, &mono, 1, vDSP_Length(frameCount))

        return DecodedAudioFrame(
            monoSamples: mono,
            sampleRate: Float(asbd.mSampleRate)
        )
    }

    nonisolated private static func accumulate(
        samples: UnsafePointer<Float>,
        frameCount: Int,
        channelsInBuffer: Int,
        scale: Float,
        into mono: inout [Float]
    ) {
        for frame in 0..<frameCount {
            let base = frame * channelsInBuffer
            for channel in 0..<channelsInBuffer {
                mono[frame] += samples[base + channel] * scale
            }
        }
    }
}
