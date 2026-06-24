import Foundation

enum IslandPresentation: Equatable, Sendable {
    case compact
    case expanding(IslandCard)
    case expanded(IslandCard)
    case collapsing(IslandCard)

    var expandsSurface: Bool {
        switch self {
        case .expanding, .expanded, .collapsing:
            true
        case .compact:
            false
        }
    }

    var showsExpandedDetails: Bool {
        if case .expanded = self { return true }
        return false
    }

    var card: IslandCard? {
        switch self {
        case .compact:
            nil
        case .expanding(let card), .expanded(let card), .collapsing(let card):
            card
        }
    }
}
