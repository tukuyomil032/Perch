import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var isExpanded = false
    var activeCard: IslandCard = .idle
}
