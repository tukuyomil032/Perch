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
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
        return URLSession(configuration: config)
    }()

    func fetchLyrics(title: String, artist: String, album: String?) async -> [LyricsLine]? {
        let key = "\(title)|\(artist)"
        if let cached = cache[key] { return cached.isEmpty ? nil : cached }

        if let lines = await fetchGet(title: title, artist: artist) {
            cache[key] = lines
            return lines
        }
        if let lines = await fetchSearch(title: title, artist: artist, album: album) {
            cache[key] = lines
            return lines
        }
        // Only cache as "no lyrics" when the failure was not due to task cancellation.
        // A cancelled fetch should be retried on next play.
        if !Task.isCancelled {
            cache[key] = []
        }
        return nil
    }

    private func fetchGet(title: String, artist: String) async -> [LyricsLine]? {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        guard let url = components.url else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let synced = json["syncedLyrics"] as? String, !synced.isEmpty
            else { return nil }
            let lines = LRCParser.parse(synced)
            return lines.isEmpty ? nil : lines
        } catch {
            logger.debug("LyricsStore /api/get failed: \(error)")
            return nil
        }
    }

    private func fetchSearch(title: String, artist: String, album: String?) async -> [LyricsLine]? {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        var queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        if let album { queryItems.append(URLQueryItem(name: "album_name", value: album)) }
        components.queryItems = queryItems
        guard let url = components.url else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            guard let results = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else { return nil }
            for result in results {
                guard let synced = result["syncedLyrics"] as? String, !synced.isEmpty else { continue }
                let lines = LRCParser.parse(synced)
                if !lines.isEmpty { return lines }
            }
            return nil
        } catch {
            logger.debug("LyricsStore /api/search failed: \(error)")
            return nil
        }
    }
}
