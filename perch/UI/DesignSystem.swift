import SwiftUI

enum DesignSystem {
    static let pillCornerRadius: CGFloat = 17
    static let cardCornerRadius: CGFloat = 28
    static let cardPadding: CGFloat = 16
    static let gridUnit: CGFloat = 4

    static let springAnimation = Animation.spring(response: 0.32, dampingFraction: 0.82)
    static let expandAnimation = Animation.spring(response: 0.35, dampingFraction: 0.86)
    static let subtleAnimation = Animation.easeInOut(duration: 0.2)
}
