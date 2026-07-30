import SwiftUI

enum DesignSystem {
    static let cardPadding: CGFloat = 16
    static let gridUnit: CGFloat = 4

    /// Rich mode's Home module (`AtollStyleExpandedView`) lays out a 3-column
    /// NowPlayingCard/lyrics/CalendarWidget row that needs more room than Minimal
    /// mode's single-column widget stack. Applied only when Rich mode is actually
    /// rendering that layout — see `ExpandedIslandView.minExpandedWidth`.
    static let richModeMinWidth: CGFloat = 680

    /// Fallback height for `AtollStyleExpandedView`'s center column before its real
    /// height (measured from the left column) is known — the value for one frame only,
    /// not a layout target. See `AtollStyleExpandedView.leftColumnHeight`.
    static let atollColumnFallbackHeight: CGFloat = 240

    /// Content-level feedback: tab/module selection capsules, active-card switches.
    /// Not the notch shell itself — see `shellOpen`/`shellClose` for that.
    static let springAnimation = Animation.spring(response: 0.32, dampingFraction: 0.82)

    /// The notch shell's expand animation, applied via `Nook.transitionConfiguration`
    /// in `IslandHost`. Deliberately underdamped (a touch of overshoot) — asymmetric
    /// with `shellClose`, per docs/SwiftUI-Animation-Architecture-Handbook-ja.md §4.3
    /// ("展開と収納は非対称にする") and its §3.1 Motion Token example.
    static let shellOpen = Animation.spring(response: 0.42, dampingFraction: 0.82)

    /// The notch shell's collapse animation. Critically damped — no bounce, so the
    /// shell settles flush against the menu bar instead of wobbling on the way down.
    static let shellClose = Animation.spring(response: 0.46, dampingFraction: 1.0)

    // AI provider brand colors
    static let claudeAmber = Color(red: 0.851, green: 0.467, blue: 0.024)  // #d97706
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
