import Foundation

enum IslandCard: String, CaseIterable, Identifiable {
    case idle
    case aiUsage
    case nowPlaying
    case fileShelf
    case devStatus
    case hud

    var id: String { rawValue }
}
