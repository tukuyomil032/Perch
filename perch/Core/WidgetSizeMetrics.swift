import Foundation

/// Single source of truth for widget row heights, keyed by `WidgetSize`.
///
/// Previously duplicated as private `[WidgetSize: CGFloat]` literals in both
/// `AppState.expandedWindowHeight` and `ExpandedIslandView.widgetSizeHeights`.
/// Consolidated here so the two call sites can't drift.
///
/// Deliberately an exhaustive `switch`, not a `[WidgetSize: CGFloat]` dictionary with
/// a fallback default: a dictionary lookup would silently fall back to a default
/// height if `WidgetSize` ever grows a new case, with no compiler signal that the
/// table is now incomplete. The switch forces a compile error instead, so a future
/// case addition can't ship with an unintended height.
nonisolated enum WidgetSizeMetrics {
    static func height(for size: WidgetSize) -> CGFloat {
        switch size {
        case .mini: 36
        case .compact: 52
        case .standard: 264
        case .full: 360
        }
    }
}
