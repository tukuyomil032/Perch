import Foundation
import Logging

@MainActor
@Observable
final class AppState {
    var isExpanded: Bool = false
    var activeCard: IslandCard = .idle
    var activePreset: IslandPreset = .music
    var latestError: String?
    var isPhysicalNotch: Bool = false

    var expandedWindowHeight: CGFloat {
        activePreset.expandedHeight
    }

    /// Compact window width: 20px wider than pill content to give buffer for scaleEffect (max 1.05×).
    /// single: content 150px → window 170px (150×1.05=157.5 < 170 ✓)
    /// dual:   content ~158px → window 190px (158×1.05=165.9 < 190 ✓)
    var compactWindowWidth: CGFloat {
        let isMusicActive = nowPlayingManager.currentState != nil
        let isAIActive = aiUsageStore.activeUsage != nil
        return (isMusicActive && isAIActive) ? 190 : 170
    }

    /// Compact window height: 10px taller than pill content for scaleEffect buffer.
    /// pill content 34px → window 44px (34×1.05=35.7 < 44 ✓)
    var compactWindowHeight: CGFloat { 44 }

    var openSettingsAction: (() -> Void)?

    let nowPlayingManager = NowPlayingManager()
    let aiUsageStore = AIUsageStore()

    private let logger = Logger(label: "com.tukuyomi032.perch.AppState")

    func expand(to card: IslandCard) {
        logger.debug("Expanding island to card: \(card)")
        activeCard = card
        isExpanded = true
    }

    func collapse() {
        logger.debug("Collapsing island")
        isExpanded = false
    }
}
