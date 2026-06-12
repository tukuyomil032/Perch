import Foundation

enum IslandPreset: String, CaseIterable, Identifiable {
    case music = "Music"
    case ai = "AI"
    // Future: named presets like Daily/Dev/Focus will be implemented in Phase 4 Preset System

    var id: String { rawValue }

    /// Window height for expanded island in this preset (floatingPill mode).
    var expandedHeight: CGFloat {
        switch self {
        case .music: return 280
        case .ai: return 320
        }
    }
}
