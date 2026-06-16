import AppKit
import SwiftUI

struct ArtworkPalette {
    let highlight: Color
    let primary: Color
    let secondary: Color

    var gradientColors: [Color] {
        [highlight, primary, secondary]
    }

    static let fallback = ArtworkPalette(
        highlight: .white,
        primary: .white.opacity(0.82),
        secondary: .white.opacity(0.38)
    )
}

extension NSImage {
    /// Extracts two genuinely different representative hues from the artwork.
    /// This is intentionally more useful for a tiny activity gradient than a
    /// single RGB average or one hue with three opacity values.
    func dynamicIslandPalette() -> ArtworkPalette {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .fallback
        }

        let side = 48
        let bytesPerPixel = 4
        var pixels = [UInt8](repeating: 0, count: side * side * bytesPerPixel)

        guard
            let context = CGContext(
                data: &pixels,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * bytesPerPixel,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return .fallback
        }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        let bucketCount = 24
        var buckets = [HueBucket](repeating: HueBucket(), count: bucketCount)

        for pixelIndex in 0..<(side * side) {
            let offset = pixelIndex * bytesPerPixel
            let alpha = Double(pixels[offset + 3]) / 255
            guard alpha > 0.5 else { continue }

            let red = Double(pixels[offset]) / 255
            let green = Double(pixels[offset + 1]) / 255
            let blue = Double(pixels[offset + 2]) / 255
            let hsv = Self.rgbToHSV(red: red, green: green, blue: blue)

            // Ignore almost-black pixels and near-white neutral backgrounds.
            guard hsv.brightness > 0.055 else { continue }
            if hsv.brightness > 0.97, hsv.saturation < 0.12 { continue }
            guard hsv.saturation > 0.08 else { continue }

            // Population remains the main signal. Saturation only nudges the
            // result so a tiny neon accent cannot beat the artwork's main area.
            let midBrightnessPreference = 1 - abs(hsv.brightness - 0.62)
            let weight =
                (0.42 + 0.58 * hsv.saturation)
                * (0.80 + 0.20 * midBrightnessPreference)

            let bucketIndex = min(
                bucketCount - 1,
                Int(hsv.hue * Double(bucketCount))
            )
            buckets[bucketIndex].add(
                red: red,
                green: green,
                blue: blue,
                saturation: hsv.saturation,
                brightness: hsv.brightness,
                weight: weight
            )
        }

        guard
            let primaryIndex = buckets.indices.max(by: {
                buckets[$0].dominanceScore < buckets[$1].dominanceScore
            }), buckets[primaryIndex].weight > 0
        else {
            return Self.neutralPalette(from: pixels, pixelCount: side * side)
        }

        let primaryHSV = Self.tunedHSV(for: buckets[primaryIndex], role: .primary)

        let secondaryIndex = buckets.indices
            .filter { index in
                index != primaryIndex
                    && buckets[index].weight > 0
                    && Self.circularBucketDistance(
                        index,
                        primaryIndex,
                        bucketCount: bucketCount
                    ) >= 2
            }
            .max { lhs, rhs in
                let lhsDistance = Self.normalizedHueDistance(
                    lhs,
                    primaryIndex,
                    bucketCount: bucketCount
                )
                let rhsDistance = Self.normalizedHueDistance(
                    rhs,
                    primaryIndex,
                    bucketCount: bucketCount
                )
                let lhsScore = buckets[lhs].dominanceScore * (0.45 + 1.25 * lhsDistance)
                let rhsScore = buckets[rhs].dominanceScore * (0.45 + 1.25 * rhsDistance)
                return lhsScore < rhsScore
            }

        let secondaryHSV: HSV
        if let secondaryIndex {
            secondaryHSV = Self.tunedHSV(for: buckets[secondaryIndex], role: .secondary)
        } else {
            // Monochromatic artwork: keep the hue but create real luminance and
            // saturation contrast rather than inventing an unrelated hue.
            secondaryHSV = HSV(
                hue: primaryHSV.hue,
                saturation: max(0.34, primaryHSV.saturation * 0.76),
                brightness: max(0.40, primaryHSV.brightness * 0.64)
            )
        }

        let highlightHSV = HSV(
            hue: primaryHSV.hue,
            saturation: max(0.22, primaryHSV.saturation * 0.56),
            brightness: min(1, primaryHSV.brightness + 0.17)
        )

        return ArtworkPalette(
            highlight: Self.color(from: highlightHSV, opacity: 0.98),
            primary: Self.color(from: primaryHSV, opacity: 0.96),
            secondary: Self.color(from: secondaryHSV, opacity: 0.92)
        )
    }

    /// Backward-compatible API for existing background visualizers.
    func dominantColor() -> Color {
        dynamicIslandPalette().primary
    }

    private enum PaletteRole {
        case primary
        case secondary
    }

    private struct HSV {
        let hue: Double
        let saturation: Double
        let brightness: Double
    }

    private struct HueBucket {
        var weight: Double = 0
        var population: Int = 0
        var weightedRed: Double = 0
        var weightedGreen: Double = 0
        var weightedBlue: Double = 0
        var weightedSaturation: Double = 0
        var weightedBrightness: Double = 0

        mutating func add(
            red: Double,
            green: Double,
            blue: Double,
            saturation: Double,
            brightness: Double,
            weight: Double
        ) {
            self.weight += weight
            population += 1
            weightedRed += red * weight
            weightedGreen += green * weight
            weightedBlue += blue * weight
            weightedSaturation += saturation * weight
            weightedBrightness += brightness * weight
        }

        var dominanceScore: Double {
            guard weight > 0 else { return 0 }
            let averageSaturation = weightedSaturation / weight
            return Double(population) * (0.72 + 0.28 * averageSaturation)
        }

        var averageRGB: (red: Double, green: Double, blue: Double) {
            guard weight > 0 else { return (1, 1, 1) }
            return (
                weightedRed / weight,
                weightedGreen / weight,
                weightedBlue / weight
            )
        }
    }

    private static func tunedHSV(for bucket: HueBucket, role: PaletteRole) -> HSV {
        let rgb = bucket.averageRGB
        let source = rgbToHSV(red: rgb.red, green: rgb.green, blue: rgb.blue)

        switch role {
        case .primary:
            return HSV(
                hue: source.hue,
                saturation: min(0.94, max(0.46, source.saturation * 1.08)),
                brightness: min(0.92, max(0.62, source.brightness))
            )
        case .secondary:
            return HSV(
                hue: source.hue,
                saturation: min(0.90, max(0.40, source.saturation)),
                brightness: min(0.86, max(0.48, source.brightness * 0.88))
            )
        }
    }

    private static func neutralPalette(from pixels: [UInt8], pixelCount: Int) -> ArtworkPalette {
        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var count = 0.0

        for index in 0..<pixelCount {
            let offset = index * 4
            let alpha = Double(pixels[offset + 3]) / 255
            guard alpha > 0.5 else { continue }
            red += Double(pixels[offset]) / 255
            green += Double(pixels[offset + 1]) / 255
            blue += Double(pixels[offset + 2]) / 255
            count += 1
        }

        guard count > 0 else { return .fallback }
        let hsv = rgbToHSV(red: red / count, green: green / count, blue: blue / count)
        let base = HSV(
            hue: hsv.hue,
            saturation: min(0.22, hsv.saturation),
            brightness: min(0.88, max(0.58, hsv.brightness))
        )

        return ArtworkPalette(
            highlight: color(
                from: HSV(
                    hue: base.hue,
                    saturation: base.saturation * 0.5,
                    brightness: min(1, base.brightness + 0.16)
                ),
                opacity: 0.96
            ),
            primary: color(from: base, opacity: 0.90),
            secondary: color(
                from: HSV(
                    hue: base.hue,
                    saturation: base.saturation,
                    brightness: max(0.36, base.brightness * 0.62)
                ),
                opacity: 0.78
            )
        )
    }

    private static func rgbToHSV(red: Double, green: Double, blue: Double) -> HSV {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum

        let saturation = maximum == 0 ? 0 : delta / maximum
        var hue = 0.0

        if delta > 0 {
            if maximum == red {
                hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
            } else if maximum == green {
                hue = (blue - red) / delta + 2
            } else {
                hue = (red - green) / delta + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }

        return HSV(hue: hue, saturation: saturation, brightness: maximum)
    }

    private static func color(from hsv: HSV, opacity: Double) -> Color {
        Color(
            nsColor: NSColor(
                calibratedHue: CGFloat(hsv.hue),
                saturation: CGFloat(hsv.saturation),
                brightness: CGFloat(hsv.brightness),
                alpha: CGFloat(opacity)
            )
        )
    }

    private static func circularBucketDistance(
        _ lhs: Int,
        _ rhs: Int,
        bucketCount: Int
    ) -> Int {
        let direct = abs(lhs - rhs)
        return min(direct, bucketCount - direct)
    }

    private static func normalizedHueDistance(
        _ lhs: Int,
        _ rhs: Int,
        bucketCount: Int
    ) -> Double {
        Double(circularBucketDistance(lhs, rhs, bucketCount: bucketCount))
            / Double(bucketCount / 2)
    }
}
