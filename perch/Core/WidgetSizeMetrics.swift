import Foundation

/// Single source of truth for widget row heights, keyed by `WidgetSize`.
///
/// Previously duplicated as private `[WidgetSize: CGFloat]` literals in both
/// `AppState.expandedWindowHeight` and `ExpandedIslandView.widgetSizeHeights`.
/// Consolidated here so the two call sites can't drift.
nonisolated enum WidgetSizeMetrics {
    static let heights: [WidgetSize: CGFloat] = [
        .mini: 36,
        .compact: 52,
        .standard: 264,
        .full: 360,
    ]

    /// The fallback height for a size missing from `heights` (shouldn't happen given
    /// `WidgetSize` is exhaustively covered above, but callers historically used 44
    /// as a defensive default).
    static let fallbackHeight: CGFloat = 44

    static func height(for size: WidgetSize) -> CGFloat {
        heights[size] ?? fallbackHeight
    }
}
