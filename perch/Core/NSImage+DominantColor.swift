import AppKit
import SwiftUI

extension NSImage {
    /// Extracts the dominant color by saturation-weighted pixel sampling.
    /// Weights vivid pixels by saturation² so dark/muted backgrounds (e.g. ClariS ALIVE)
    /// don't pull the result toward gray when a bright accent color is present.
    func dominantColor() -> Color {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .white.opacity(0.8)
        }

        let side = 32
        let bytesPerPixel = 4
        let bytesPerRow = side * bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: side * side * bytesPerPixel)

        guard
            let ctx = CGContext(
                data: &pixelData,
                width: side, height: side,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return .white.opacity(0.8) }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        var weightedR: Double = 0
        var weightedG: Double = 0
        var weightedB: Double = 0
        var totalWeight: Double = 0

        for i in 0..<(side * side) {
            let base = i * bytesPerPixel
            let r = Double(pixelData[base]) / 255.0
            let g = Double(pixelData[base + 1]) / 255.0
            let b = Double(pixelData[base + 2]) / 255.0

            let maxC = max(r, g, b)
            let minC = min(r, g, b)
            let saturation = maxC > 0 ? (maxC - minC) / maxC : 0

            // saturation² heavily downweights grays/darks and upweights vivid colors
            let weight = saturation * saturation
            weightedR += r * weight
            weightedG += g * weight
            weightedB += b * weight
            totalWeight += weight
        }

        // Fallback: if image has almost no vivid pixels, use simple average
        guard totalWeight > 0.5 else {
            return Self.simpleAverageColor(pixels: pixelData, count: side * side)
        }

        var r = weightedR / totalWeight
        var g = weightedG / totalWeight
        var b = weightedB / totalWeight

        // Normalize: bring max channel to 1.0 for maximum vibrancy
        let maxC = max(r, g, b)
        if maxC > 0 {
            r = min(r / maxC, 1.0)
            g = min(g / maxC, 1.0)
            b = min(b / maxC, 1.0)
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
