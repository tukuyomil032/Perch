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

/// Normalization helpers for titles and artists as delivered by Apple Music /
/// Spotify. The originals often carry annotations like "(feat. X)" or
/// "-TV Size-" that break LRCLIB's strict-match `/api/get` and fuzzy `/api/search`.
enum LyricsNormalizer {
    /// Strip parenthesized annotations (feat., versions, TV/Movie size, remaster
    /// tags, deluxe/edition tags, live/acoustic markers) and bracketed
    /// annotations. Also drops trailing "-XX-" style version tags. Returns the
    /// input unchanged when no annotation is found.
    nonisolated static func stripTitleAnnotations(_ title: String) -> String {
        var s = title
        // (feat. X) / (with X) / (ft. X) — case-insensitive, quote-tolerant
        s = s.replacingOccurrences(
            of: #"\s*\([^)]*(feat\.|ft\.|with) [^)]*\)"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        // (TV Size) / (Movie Version) / (Anime OP) / (Game Ver.) etc.
        s = s.replacingOccurrences(
            of:
                #"\s*\((TV|Movie|Anime|Game|Original|Remaster|Deluxe|Single|Extended|Cover|Live|Acoustic|Version|Instrumental|Karaoke|Radio|Album|Studio)[^)]*\)"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        // [Remaster] / [Deluxe Edition] / [2020 Remaster]
        s = s.replacingOccurrences(
            of: #"\s*\[[^\]]*\]"#,
            with: "",
            options: .regularExpression
        )
        // Trailing "-TV Version-" or " -Original Mix-" or "-Radio Edit-"
        s = s.replacingOccurrences(
            of: #"\s+-\s*[^-]+\s*-\s*$"#,
            with: "",
            options: .regularExpression
        )
        // Trailing " - Remastered 2020" / " - Single Version"
        s = s.replacingOccurrences(
            of: #"\s+-\s+(Remaster|Single|Extended|Radio|Instrumental|Live|Acoustic|Original)[^-]*$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Extract the primary artist from strings like `"Artist A & Artist B"`,
    /// `"Artist A feat. Artist B"`, `"Artist A, Artist B"`. Returns the input
    /// unchanged when no separator is present.
    nonisolated static func primaryArtist(_ artist: String) -> String {
        let separators = [
            " & ", ", ", " feat. ", " ft. ", " with ", " Feat. ", " Ft. ", " FEAT. ", " FT. ", " With ",
        ]
        var earliest = artist.endIndex
        for sep in separators {
            if let range = artist.range(of: sep, options: .caseInsensitive) {
                if range.lowerBound < earliest {
                    earliest = range.lowerBound
                }
            }
        }
        let primary =
            earliest == artist.endIndex ? artist : String(artist[..<earliest])
        return primary.trimmingCharacters(in: .whitespaces)
    }
}

actor LyricsStore {
    static let shared = LyricsStore()
    private var cache: [String: [LyricsLine]] = [:]
    /// Negative cache — remembers "we searched and found nothing" so a rapidly
    /// re-rendered card doesn't re-request the same missing lyrics on every tick.
    private var negativeCache: [String: Date] = [:]
    private static let negativeCacheTTL: TimeInterval = 600  // 10 minutes
    private let logger = Logger(label: "com.tukuyomi032.perch.LyricsStore")
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
        return URLSession(configuration: config)
    }()

    /// Backwards-compatible entry point (no duration). Prefer the overload with
    /// `duration:` when the caller has playback metadata.
    func fetchLyrics(title: String, artist: String, album: String?) async -> [LyricsLine]? {
        await fetchLyrics(title: title, artist: artist, album: album, duration: nil)
    }

    func fetchLyrics(
        title: String,
        artist: String,
        album: String?,
        duration: Double?
    ) async -> [LyricsLine]? {
        let key = "\(title)|\(artist)"
        if let cached = cache[key] { return cached }
        if let deniedAt = negativeCache[key],
            -deniedAt.timeIntervalSinceNow < Self.negativeCacheTTL
        {
            return nil
        }
        // LRCLIB requires an artist. Skip the whole chain when it's missing
        // rather than making a guaranteed-404 request.
        guard !artist.isEmpty else {
            logger.debug("Lyrics fetch skipped for '\(title)' — empty artist")
            return nil
        }

        logger.info(
            "Lyrics fetch: title='\(title)' artist='\(artist)' album='\(album ?? "nil")' duration=\(duration.map { String(format: "%.0f", $0) } ?? "nil")"
        )

        // Attempt 1: as-is, with album + duration hints
        if let lines = await lrcLibGet(
            title: title, artist: artist, album: album, duration: duration)
        {
            cache[key] = lines
            return lines
        }
        if let lines = await lrcLibSearch(title: title, artist: artist) {
            cache[key] = lines
            return lines
        }

        // Attempt 2: strip annotations from the title (feat. / TV Size / Remaster)
        let strippedTitle = LyricsNormalizer.stripTitleAnnotations(title)
        if strippedTitle != title, !strippedTitle.isEmpty {
            logger.info("Lyrics retry with stripped title: '\(strippedTitle)'")
            if let lines = await lrcLibGet(
                title: strippedTitle, artist: artist, album: album, duration: duration)
            {
                cache[key] = lines
                return lines
            }
            if let lines = await lrcLibSearch(title: strippedTitle, artist: artist) {
                cache[key] = lines
                return lines
            }
        }

        // Attempt 3: primary artist only (drop "feat. XX" / "& XX")
        let primaryArtist = LyricsNormalizer.primaryArtist(artist)
        if primaryArtist != artist, !primaryArtist.isEmpty {
            let title2 = strippedTitle.isEmpty ? title : strippedTitle
            logger.info("Lyrics retry with primary artist: '\(primaryArtist)'")
            if let lines = await lrcLibGet(
                title: title2, artist: primaryArtist, album: album, duration: duration)
            {
                cache[key] = lines
                return lines
            }
            if let lines = await lrcLibSearch(title: title2, artist: primaryArtist) {
                cache[key] = lines
                return lines
            }
        }

        // Attempt 4: LyricsKit (netease/qq/kugou) — original title/artist
        if let lines = await LyricsKitFetcher.shared.fetch(title: title, artist: artist) {
            cache[key] = lines
            return lines
        }

        negativeCache[key] = Date()
        logger.info(
            "Lyrics not found for '\(title)' by '\(artist)' — negative-cached for \(Int(Self.negativeCacheTTL))s"
        )
        return nil
    }

    private func lrcLibGet(
        title: String,
        artist: String,
        album: String?,
        duration: Double?
    ) async -> [LyricsLine]? {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        var items = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        if let album, !album.isEmpty {
            items.append(URLQueryItem(name: "album_name", value: album))
        }
        if let duration {
            items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded()))))
        }
        components.queryItems = items
        guard let url = components.url else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                logger.debug("LRCLIB /api/get HTTP \(status) for '\(title)' by '\(artist)'")
                return nil
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let synced = json["syncedLyrics"] as? String, !synced.isEmpty
            else {
                logger.debug("LRCLIB /api/get: 200 OK but no syncedLyrics for '\(title)'")
                return nil
            }
            let lines = LRCParser.parse(synced)
            logger.debug("LRCLIB /api/get: parsed \(lines.count) lines for '\(title)'")
            return lines.isEmpty ? nil : lines
        } catch {
            logger.debug("LRCLIB /api/get failed: \(error)")
            return nil
        }
    }

    private func lrcLibSearch(title: String, artist: String) async -> [LyricsLine]? {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        guard let url = components.url else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                logger.debug("LRCLIB /api/search HTTP \(status) for '\(title)' by '\(artist)'")
                return nil
            }
            guard let results = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else { return nil }
            logger.debug("LRCLIB /api/search: \(results.count) results for '\(title)'")
            for result in results {
                guard let synced = result["syncedLyrics"] as? String, !synced.isEmpty else {
                    continue
                }
                let lines = LRCParser.parse(synced)
                if !lines.isEmpty { return lines }
            }
            return nil
        } catch {
            logger.debug("LRCLIB /api/search failed: \(error)")
            return nil
        }
    }
}
