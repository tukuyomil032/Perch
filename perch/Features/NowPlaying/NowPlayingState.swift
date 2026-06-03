// perch/Features/NowPlaying/NowPlayingState.swift
import AppKit

enum MusicSource: String, Sendable, Equatable {
    case spotify = "Spotify"
    case appleMusic = "Apple Music"
    case youTubeMusic = "YouTube Music"
    case mrMediaRemote = "MRMediaRemote"

    var displayName: String { rawValue }
}

@MainActor
struct NowPlayingState {
    let title: String
    let artist: String
    let album: String?
    let artwork: NSImage?
    let isPlaying: Bool
    let duration: TimeInterval?
    let elapsedTime: TimeInterval?
    let timestamp: Date?
    let source: MusicSource

    var progress: Double {
        guard let elapsed = elapsedTime, let total = duration, total > 0 else { return 0 }
        return min(elapsed / total, 1.0)
    }

    var formattedElapsed: String {
        guard let t = elapsedTime else { return "-:--" }
        return formatTime(t)
    }

    func liveElapsed(at date: Date) -> TimeInterval? {
        guard let elapsed = elapsedTime else { return nil }
        guard isPlaying, let ts = timestamp else { return elapsed }
        let raw = elapsed + date.timeIntervalSince(ts)
        if let total = duration { return min(max(0, raw), total) }
        return max(0, raw)
    }

    func liveProgress(at date: Date) -> Double {
        guard let elapsed = liveElapsed(at: date), let total = duration, total > 0 else { return 0 }
        return min(elapsed / total, 1.0)
    }

    func liveFormattedElapsed(at date: Date) -> String {
        guard let t = liveElapsed(at: date) else { return "-:--" }
        let s = max(0, Int(t))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    func liveRemaining(at date: Date) -> String? {
        guard let total = duration else { return nil }
        let elapsed = liveElapsed(at: date) ?? (elapsedTime ?? 0)
        let remaining = max(0, total - elapsed)
        let s = Int(remaining)
        return String(format: "-%d:%02d", s / 60, s % 60)
    }

    var formattedDuration: String {
        guard let t = duration else { return "-:--" }
        return formatTime(t)
    }

    // Internal full init used for artwork enrichment and position updates
    init(
        title: String, artist: String, album: String?, artwork: NSImage?,
        isPlaying: Bool, duration: TimeInterval?, elapsedTime: TimeInterval?,
        timestamp: Date?, source: MusicSource
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artwork = artwork
        self.isPlaying = isPlaying
        self.duration = duration
        self.elapsedTime = elapsedTime
        self.timestamp = timestamp
        self.source = source
    }

    func enriched(artwork: NSImage?) -> NowPlayingState {
        NowPlayingState(
            title: title, artist: artist, album: album, artwork: artwork,
            isPlaying: isPlaying, duration: duration, elapsedTime: elapsedTime,
            timestamp: timestamp, source: source
        )
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // Returns nil when no meaningful track info is present
    init?(from info: [String: Any]?) {
        guard let info, let title = info[MRInfoKey.title] as? String, !title.isEmpty else {
            return nil
        }
        self.title = title
        self.artist = info[MRInfoKey.artist] as? String ?? ""
        self.album = info[MRInfoKey.album] as? String
        self.isPlaying = (info[MRInfoKey.playbackRate] as? Double ?? 0) > 0
        self.duration = info[MRInfoKey.duration] as? TimeInterval
        self.elapsedTime = info[MRInfoKey.elapsedTime] as? TimeInterval
        self.timestamp = info[MRInfoKey.timestamp] as? Date
        self.source = .mrMediaRemote
        if let data = info[MRInfoKey.artworkData] as? Data {
            self.artwork = NSImage(data: data)
        } else {
            self.artwork = nil
        }
    }
}

extension NowPlayingState: Equatable {
    // nonisolated required: Equatable.== is a nonisolated protocol requirement.
    // NSImage is non-Sendable — accessing it from nonisolated context is rejected by Swift 6.
    // title/artist/isPlaying/source are Sendable and cover all meaningful track-change signals.
    nonisolated static func == (lhs: NowPlayingState, rhs: NowPlayingState) -> Bool {
        lhs.title == rhs.title && lhs.artist == rhs.artist && lhs.isPlaying == rhs.isPlaying && lhs.source == rhs.source
    }
}

// MARK: - DistributedNotification initializers

extension NowPlayingState {
    /// Spotify: constructed from pre-extracted Sendable scalars (caller extracts from userInfo
    /// in a nonisolated context; only Sendable values cross the isolation boundary).
    init?(
        spotifyPlayerState playerState: String,
        title: String,
        artist: String,
        album: String?,
        durationMs: Double?,
        position: Double?
    ) {
        guard playerState != "Stopped", !title.isEmpty else { return nil }
        self.title = title
        self.artist = artist
        self.album = album
        self.isPlaying = playerState == "Playing"
        self.duration = durationMs.map { $0 / 1000.0 }  // ms → seconds
        self.elapsedTime = position  // already in seconds
        self.timestamp = Date()
        self.artwork = nil
        self.source = .spotify
    }

    /// Apple Music: constructed from pre-extracted Sendable scalars.
    init?(
        appleMusicPlayerState playerState: String,
        title: String,
        artist: String,
        album: String?,
        totalTime: Double?
    ) {
        guard playerState != "Stopped", !title.isEmpty else { return nil }
        self.title = title
        self.artist = artist
        self.album = album
        self.isPlaying = playerState == "Playing"
        self.duration = totalTime.map { $0 / 1000.0 }  // Total Time is in ms (iTunes legacy)
        self.elapsedTime = nil
        self.timestamp = nil
        self.artwork = nil
        self.source = .appleMusic
    }

    /// YouTube Music: parse Chrome window title "Artist - Song - YouTube Music".
    /// isPlaying is always true — Chrome title doesn't change when paused (known limitation, future phase).
    init?(fromYouTubeMusicTitle windowTitle: String) {
        let cleaned =
            windowTitle
            .replacingOccurrences(of: " - YouTube Music", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, cleaned != "YouTube Music" else { return nil }
        let parts = cleaned.components(separatedBy: " - ")
        if parts.count >= 2 {
            self.artist = parts[0]
            self.title = parts[1...].joined(separator: " - ")
        } else {
            self.artist = ""
            self.title = cleaned
        }
        self.album = nil
        self.isPlaying = true
        self.duration = nil
        self.elapsedTime = nil
        self.timestamp = nil
        self.artwork = nil
        self.source = .youTubeMusic
    }
}
