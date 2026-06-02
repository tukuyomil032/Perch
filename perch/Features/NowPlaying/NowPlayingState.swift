// perch/Features/NowPlaying/NowPlayingState.swift
import AppKit

struct NowPlayingState {
    let title: String
    let artist: String
    let album: String?
    let artwork: NSImage?
    let isPlaying: Bool
    let duration: TimeInterval?
    let elapsedTime: TimeInterval?

    var progress: Double {
        guard let elapsed = elapsedTime, let total = duration, total > 0 else { return 0 }
        return min(elapsed / total, 1.0)
    }

    var formattedElapsed: String {
        guard let t = elapsedTime else { return "-:--" }
        return formatTime(t)
    }

    var formattedDuration: String {
        guard let t = duration else { return "-:--" }
        return formatTime(t)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
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
        if let data = info[MRInfoKey.artworkData] as? Data {
            self.artwork = NSImage(data: data)
        } else {
            self.artwork = nil
        }
    }
}

extension NowPlayingState: Equatable {
    static func == (lhs: NowPlayingState, rhs: NowPlayingState) -> Bool {
        lhs.title == rhs.title && lhs.artist == rhs.artist && lhs.isPlaying == rhs.isPlaying
    }
}
