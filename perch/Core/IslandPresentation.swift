import Foundation

enum IslandPresentation: Equatable, Sendable {
    case compact
    case expanded(IslandCard)
    case collapsing(IslandCard)

    var expandsSurface: Bool {
        switch self {
        case .expanded:
            true
        case .compact, .collapsing:
            false
        }
    }

    var card: IslandCard? {
        switch self {
        case .compact:
            nil
        case .expanded(let card), .collapsing(let card):
            card
        }
    }
}
