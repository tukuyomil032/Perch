import AppKit
import SwiftUI

extension NSImage {
    /// Extracts the dominant color using a hue-histogram approach.
    ///
    /// Filters to vibrant pixels (saturation > 0.30, brightness > 0.20), finds the
    /// most-weighted hue bucket among them, then returns the average color of that bucket.
    /// This correctly prioritises dominant-area hues (e.g. IRIS OUT's blue-purple hair)
    /// over small-but-vivid accents (e.g. the red arm), unlike the old CIAreaAverage
    /// or saturation²-weighted approaches.
    func dominantColor() -> Color {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .white.opacity(0.8)
        }

        let side = 32
        let bytesPerPixel = 4
        var pixelData = [UInt8](repeating: 0, count: side * side * bytesPerPixel)

        guard
            let ctx = CGContext(
                data: &pixelData,
                width: side, height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * bytesPerPixel,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return .white.opacity(0.8) }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        // Hue histogram: 16 buckets × 22.5° each
        let bucketCount = 16
        var bucketWeight = [Double](repeating: 0, count: bucketCount)
        var bucketR = [Double](repeating: 0, count: bucketCount)
        var bucketG = [Double](repeating: 0, count: bucketCount)
        var bucketB = [Double](repeating: 0, count: bucketCount)

        for i in 0..<(side * side) {
            let base = i * bytesPerPixel
            let r = Double(pixelData[base]) / 255.0
            let g = Double(pixelData[base + 1]) / 255.0
            let b = Double(pixelData[base + 2]) / 255.0

            let maxC = max(r, g, b)
            let minC = min(r, g, b)
            let delta = maxC - minC

            // Skip near-black and achromatic pixels
            guard maxC > 0.20, delta / maxC > 0.30 else { continue }

            // Compute hue in [0, 1)
            var hue: Double
            if maxC == r {
                hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6.0)
                if hue < 0 { hue += 6 }
                hue /= 6
            } else if maxC == g {
                hue = ((b - r) / delta + 2) / 6
            } else {
                hue = ((r - g) / delta + 4) / 6
            }

            // Weight by saturation × brightness so vivid, bright pixels count more
            let weight = (delta / maxC) * maxC
            let bucket = min(bucketCount - 1, Int(hue * Double(bucketCount)))
            bucketWeight[bucket] += weight
            bucketR[bucket] += r * weight
            bucketG[bucket] += g * weight
            bucketB[bucket] += b * weight
        }

        // Find the dominant hue bucket
        guard let winIdx = bucketWeight.indices.max(by: { bucketWeight[$0] < bucketWeight[$1] }),
            bucketWeight[winIdx] > 0
        else {
            return Self.simpleAverageColor(pixels: pixelData, count: side * side)
        }

        let w = bucketWeight[winIdx]
        var r = bucketR[winIdx] / w
        var g = bucketG[winIdx] / w
        var b = bucketB[winIdx] / w

        // Soft brightness boost: bring dark results up to at least 60% brightness
        let brightness = max(r, g, b)
        if brightness < 0.6, brightness > 0 {
            let scale = 0.6 / brightness
            r = min(r * scale, 1.0)
            g = min(g * scale, 1.0)
            b = min(b * scale, 1.0)
        }

        return Color(red: r, green: g, blue: b).opacity(0.9)
    }

    private static func simpleAverageColor(pixels: [UInt8], count: Int) -> Color {
        var r: Double = 0
        var g: Double = 0
        var b: Double = 0
        for i in 0..<count {
            let base = i * 4
            r += Double(pixels[base]) / 255.0
            g += Double(pixels[base + 1]) / 255.0
            b += Double(pixels[base + 2]) / 255.0
        }
        let n = Double(count)
        let maxC = max(r / n, g / n, b / n)
        guard maxC > 0.15 else { return .white.opacity(0.8) }
        let boost = min(1.0 / maxC, 1.5)
        return Color(
            red: min(r / n * boost, 1.0),
            green: min(g / n * boost, 1.0),
            blue: min(b / n * boost, 1.0)
        ).opacity(0.9)
    }
}
