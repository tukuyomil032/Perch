import CoreGraphics

enum IslandMode: Equatable {
    case physicalNotch(notchSize: CGSize)
    case floatingPill
}
