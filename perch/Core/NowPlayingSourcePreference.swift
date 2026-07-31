import Foundation

/// Which Now Playing source(s) Perch pays attention to, set from Settings' Now Playing tab.
///
/// `.auto` keeps the original behavior — whichever source is actually playing wins, via
/// `NowPlayingManager`'s existing priority arbitration (`sourcePriority(_:)`). Picking a
/// specific source makes it exclusive: activity from every other source is ignored
/// entirely, matching the single-select "Music Source" picker in comparable apps.
enum NowPlayingSourcePreference: String, CaseIterable, Sendable, Identifiable {
    case auto
    case spotify
    case appleMusic
    case youTubeMusic

    nonisolated var id: Self { self }

    nonisolated var displayNameKey: String {
        switch self {
        case .auto: "settings.nowplaying_source.auto"
        case .spotify: "settings.spotify"
        case .appleMusic: "settings.apple_music"
        case .youTubeMusic: "settings.youtube_music"
        }
    }

    /// The `MusicSource` this preference restricts activity to, or `nil` for `.auto`
    /// (no restriction — every source is allowed through).
    nonisolated var exclusiveSource: MusicSource? {
        switch self {
        case .auto: nil
        case .spotify: .spotify
        case .appleMusic: .appleMusic
        case .youTubeMusic: .youTubeMusic
        }
    }
}
