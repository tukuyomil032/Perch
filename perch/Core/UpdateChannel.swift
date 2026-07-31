import Foundation

/// The Sparkle appcast channels a person can opt into from Settings.
///
/// Sparkle always accepts items without a channel. Adding `beta` therefore keeps stable
/// releases available while also admitting beta items from the same appcast.
enum UpdateChannel: String, CaseIterable, Sendable, Identifiable {
    case stable
    case beta

    nonisolated var id: Self { self }

    nonisolated var allowedChannels: Set<String> {
        switch self {
        case .stable:
            []
        case .beta:
            ["beta"]
        }
    }

    nonisolated var displayNameKey: String {
        switch self {
        case .stable: "settings.updates.channel.stable"
        case .beta: "settings.updates.channel.beta"
        }
    }
}
