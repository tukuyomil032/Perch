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
}

// MARK: - Shared UI Components

struct VibrancyBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
