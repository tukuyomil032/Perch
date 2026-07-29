import Foundation
import Testing

@testable import perch

@Suite("IslandModuleContent")
struct IslandModuleContentTests {
    @Test("nowPlaying routes to presetDriven")
    func nowPlayingIsPresetDriven() {
        #expect(IslandModuleContent.content(for: .nowPlaying) == .presetDriven)
    }

    @Test("aiUsage routes to aiUsageDirect")
    func aiUsageIsDirect() {
        #expect(IslandModuleContent.content(for: .aiUsage) == .aiUsageDirect)
    }

    @Test("cards with no module content yet resolve to empty")
    func unimplementedCardsAreEmpty() {
        for card: IslandCard in [.idle, .fileShelf, .devStatus, .hud] {
            #expect(IslandModuleContent.content(for: card) == .empty)
        }
    }

    @Test("PresetTabBar only shows for the preset-driven module")
    func presetTabBarVisibility() {
        #expect(IslandModuleContent.showsPresetTabBar(for: .nowPlaying))
        for card: IslandCard in [.aiUsage, .idle, .fileShelf, .devStatus, .hud] {
            #expect(!IslandModuleContent.showsPresetTabBar(for: card))
        }
    }

    @Test("every IslandCard case maps to exactly one content kind")
    func allCasesAreHandled() {
        for card in IslandCard.allCases {
            _ = IslandModuleContent.content(for: card)
        }
    }
}
