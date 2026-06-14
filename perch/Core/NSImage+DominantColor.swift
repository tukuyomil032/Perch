// perch/Core/NSImage+DominantColor.swift
import AppKit
@preconcurrency import CoreImage
import SwiftUI

extension NSImage {
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Extracts the dominant color using CIAreaAverage.
    /// Skips near-black/near-white images and boosts saturation for vibrant wave colors.
    func dominantColor() -> Color {
        guard let cgRef = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .white.opacity(0.8)
        }
        let ci = CIImage(cgImage: cgRef)
        guard
            let filter = CIFilter(
                name: "CIAreaAverage",
                parameters: [
                    kCIInputImageKey: ci,
                    kCIInputExtentKey: CIVector(cgRect: ci.extent),
                ]),
            let output = filter.outputImage
        else { return .white.opacity(0.8) }

        var pixel = [UInt8](repeating: 0, count: 4)
        Self.ciContext.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB())

        let r = Double(pixel[0]) / 255.0
        let g = Double(pixel[1]) / 255.0
        let b = Double(pixel[2]) / 255.0
        let brightness = (r + g + b) / 3.0

        // Avoid near-black or near-white
        guard brightness > 0.15 && brightness < 0.92 else { return .white.opacity(0.8) }

        // Boost saturation: scale so the highest component approaches 1.0 (cap at 1.5x)
        let maxC = max(r, g, b)
        guard maxC > 0 else { return .white.opacity(0.8) }
        let boost = min(1.0 / maxC, 1.5)
        return Color(
            red: min(r * boost, 1.0),
            green: min(g * boost, 1.0),
            blue: min(b * boost, 1.0)
        ).opacity(0.9)
    }
}
