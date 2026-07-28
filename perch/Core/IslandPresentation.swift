import Foundation

/// What the island is currently showing.
///
/// Two cases, not four. The retired `.expanding` / `.collapsing` cases existed to model
/// the gap between "a transition was requested" and "it has finished", back when
/// `AppState` drove that gap itself with a 110ms open timer and a 500ms close timer. The
/// vendored surface owns transitions now and reports only settled states, which makes the
/// intermediate cases unreachable: nothing can observe them, and `AppState` no longer has
/// a timer that would set them.
///
/// `showsExpandedDetails` went with them. It meant "expanded, and done animating" — a
/// distinction from `expandsSurface` that only existed because `.expanding` and
/// `.collapsing` also expanded the surface. With two cases the two predicates are the same
/// question, so only `expandsSurface` remains.
enum IslandPresentation: Equatable, Sendable {
    case compact
    case expanded(IslandCard)

    var expandsSurface: Bool {
        switch self {
        case .expanded: true
        case .compact: false
        }
    }

    var card: IslandCard? {
        switch self {
        case .compact: nil
        case .expanded(let card): card
        }
    }
}
