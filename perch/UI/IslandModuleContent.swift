import Foundation

/// What `ExpandedIslandView` draws in its content area for a given `IslandCard`.
///
/// A pure mapping, kept outside the view so it is testable without mounting SwiftUI.
/// `.aiUsageDirect` bypasses `PresetStore` entirely — the AI Usage module always shows
/// the full AI usage screen regardless of which preset is active, since module
/// selection and preset selection are separate concepts (see Phase B design notes in
/// `docs/opennook-migration-plan.md`).
nonisolated enum IslandModuleContent: Equatable {
    case presetDriven
    case aiUsageDirect
    case empty

    static func content(for card: IslandCard) -> IslandModuleContent {
        switch card {
        case .nowPlaying: .presetDriven
        case .aiUsage: .aiUsageDirect
        case .idle, .fileShelf, .devStatus, .hud: .empty
        }
    }

    /// Whether `PresetTabBar` should be shown for this card. Only the preset-driven
    /// module (Home) has a preset concept to switch between.
    static func showsPresetTabBar(for card: IslandCard) -> Bool {
        content(for: card) == .presetDriven
    }
}
