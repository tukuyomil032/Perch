import Foundation

// Pure data types for widget sizing and positioning.
// Kept in a Foundation-only file to avoid MainActor inference from SwiftUI imports.

enum WidgetSize: String, Codable, CaseIterable, Comparable, Sendable {
    case mini
    case compact
    case standard
    case full

    private var sortOrder: Int {
        switch self {
        case .mini: 0
        case .compact: 1
        case .standard: 2
        case .full: 3
        }
    }

    static func < (lhs: WidgetSize, rhs: WidgetSize) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

enum WidgetPosition: String, Codable, Sendable {
    case main
    case sidebar
    case bottom
}
