import Foundation
import Logging

@MainActor
@Observable
final class AppState {
    var isExpanded: Bool = false
    var activeCard: IslandCard = .idle
    var activePreset: IslandPreset = .daily
    var latestError: String?
    var isPhysicalNotch: Bool = false

    var expandedWindowHeight: CGFloat {
        activePreset.expandedHeight
    }

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
