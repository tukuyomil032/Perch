// perch/Features/NowPlaying/NowPlayingState.swift
import AppKit

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
        return elapsed + date.timeIntervalSince(ts)
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

    var formattedDuration: String {
        guard let t = duration else { return "-:--" }
        return formatTime(t)
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
        if let data = info[MRInfoKey.artworkData] as? Data {
            self.artwork = NSImage(data: data)
        } else {
            self.artwork = nil
        }
    }
}

extension NowPlayingState: Equatable {
    // nonisolated required: Equatable.== is a nonisolated protocol requirement.
    // All compared properties are `let` on a value type, so nonisolated access is safe.
    // artwork uses === (reference identity): two distinct NSImage objects from different
    // data payloads (e.g. Spotify low-res → full-res deferred update) are never ===.
    nonisolated static func == (lhs: NowPlayingState, rhs: NowPlayingState) -> Bool {
        lhs.title == rhs.title && lhs.artist == rhs.artist && lhs.isPlaying == rhs.isPlaying
            && lhs.artwork === rhs.artwork
    }
}
