import Foundation

enum IslandPreset: String, CaseIterable, Identifiable {
    case daily = "Daily"
    case dev = "Dev"

    var id: String { rawValue }

    /// Window height for expanded island in this preset (floatingPill mode).
    var expandedHeight: CGFloat {
        switch self {
        case .daily: return 280
        case .dev: return 320
        }
    }
}
