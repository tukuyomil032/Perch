import Foundation
import Logging

@MainActor
@Observable
final class AppState {
    var isExpanded: Bool = false
    var activeCard: IslandCard = .idle
    var latestError: String?

    let nowPlayingManager = NowPlayingManager()

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
