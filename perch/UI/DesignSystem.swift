import QuartzCore
import SwiftUI

enum DesignSystem {
    static let pillCornerRadius: CGFloat = 17
    static let cardCornerRadius: CGFloat = 28
    static let cardPadding: CGFloat = 16
    static let gridUnit: CGFloat = 4

    static let springAnimation = Animation.spring(response: 0.32, dampingFraction: 0.82)
    static let expandAnimation = Animation.spring(response: 0.35, dampingFraction: 0.86)
    static let subtleAnimation = Animation.easeInOut(duration: 0.2)

    // AI provider brand colors
    static let claudeAmber = Color(red: 0.851, green: 0.467, blue: 0.024)  // #d97706

    enum Motion {
        static let shellDuration: TimeInterval = 0.50
        static let closeDuration: TimeInterval = 0.46

        static let shellOpen = Animation.timingCurve(
            0.20, 0.88, 0.28, 1.00,
            duration: shellDuration
        )

        static let shellClose = Animation.timingCurve(
            0.30, 0.00, 0.18, 1.00,
            duration: closeDuration
        )

        static let detailIn = Animation.timingCurve(
            0.16, 0.84, 0.25, 1.00,
            duration: 0.36
        )

        static let detailOut = Animation.timingCurve(
            0.35, 0.00, 0.35, 1.00,
            duration: 0.12
        )

        static let appKitOpenTiming = CAMediaTimingFunction(
            controlPoints: 0.20, 0.88, 0.28, 1.00
        )

        static let appKitCloseTiming = CAMediaTimingFunction(
            controlPoints: 0.30, 0.00, 0.18, 1.00
        )
    }
}

// MARK: - Color Utilities

extension Color {
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

// MARK: - Shared UI Components

struct VibrancyBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow  // deeper blur than underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
