import Foundation

enum IslandMode: Equatable {
    case physicalNotch
    case floatingPill
}

struct IslandConfiguration: Equatable {
    var mode: IslandMode
    var compactSize: CGSize
    var expandedSize: CGSize
    var topOffset: CGFloat
}
