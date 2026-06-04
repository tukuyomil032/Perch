// perch/Features/NowPlaying/LyricsStore.swift
import Foundation
import Logging

struct LyricsLine: Identifiable, Sendable {
    let id: UUID
    let timestamp: TimeInterval
    let text: String

    nonisolated init(timestamp: TimeInterval, text: String) {
        self.id = UUID()
        self.timestamp = timestamp
        self.text = text
    }
}

enum LRCParser {
    nonisolated static func parse(_ lrc: String) -> [LyricsLine] {
        let pattern = /\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)/
        return lrc.components(separatedBy: "\n").compactMap { line in
            guard let m = try? pattern.firstMatch(in: line) else { return nil }
            let min = Double(m.1) ?? 0
            let sec = Double(m.2) ?? 0
            let frac = Double(m.3) ?? 0
            let divisor = m.3.count == 3 ? 1000.0 : 100.0
            let ts = min * 60 + sec + frac / divisor
            let text = String(m.4).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            return LyricsLine(timestamp: ts, text: text)
        }.sorted { $0.timestamp < $1.timestamp }
    }
}

actor LyricsStore {
    static let shared = LyricsStore()
    private var cache: [String: [LyricsLine]] = [:]
    private let logger = Logger(label: "com.tukuyomi032.perch.LyricsStore")

    func fetchLyrics(title: String, artist: String, album: String?) async -> [LyricsLine]? {
        let key = "\(title)|\(artist)"
        if let cached = cache[key] { return cached }

        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        if let album {
            components.queryItems?.append(URLQueryItem(name: "album_name", value: album))
        }
        guard let url = components.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let synced = json["syncedLyrics"] as? String, !synced.isEmpty
            else { return nil }
            let lines = LRCParser.parse(synced)
            cache[key] = lines
            return lines.isEmpty ? nil : lines
        } catch {
            logger.debug("LyricsStore fetch failed: \(error)")
            return nil
        }
    }
}
