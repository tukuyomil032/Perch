// perch/Features/NowPlaying/ArtworkFetcher.swift
@preconcurrency import AppKit
import Foundation
import Logging

/// Fetches album artwork via AppleScript for Spotify and Apple Music.
/// `actor` isolation serializes fetches so NSAppleScript is never called concurrently.
actor ArtworkFetcher {
    static let shared = ArtworkFetcher()
    private init() {}

    private var lastSpotifyURL: String = ""
    private let logger: Logger = {
        var logger = Logger(label: "com.tukuyomi032.perch.ArtworkFetcher")
        logger.logLevel = .debug
        return logger
    }()

    // MARK: - Spotify

    /// Returns artwork data by fetching the track's artwork URL via AppleScript, then downloading it.
    func fetchSpotifyArtworkData() async -> Data? {
        let urlScript = """
            tell application "Spotify"
                if not running then return ""
                return artwork url of current track as string
            end tell
            """
        guard let urlString = await runAppleScript(urlScript),
            !urlString.isEmpty,
            urlString != lastSpotifyURL,
            let url = URL(string: urlString)
        else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            // Only recorded once the download actually succeeds — recording it earlier
            // meant a single transient failure (e.g. startup network flakiness) marked the
            // track as "tried" forever, since this same URL would never be attempted again.
            lastSpotifyURL = urlString
            return data
        } catch {
            return nil
        }
    }

    // MARK: - Apple Music

    /// Returns artwork data by reading binary image data directly from the AppleScript descriptor.
    func fetchAppleMusicArtworkData() async -> Data? {
        let logger = logger
        return await Task.detached {
            var error: NSDictionary?
            let script = NSAppleScript(
                source: """
                    tell application "Music"
                        if not running then return
                        if player state is stopped then return
                        set art to data of artwork 1 of current track
                        return art
                    end tell
                    """)
            let result = script?.executeAndReturnError(&error)
            if let error {
                // -1743 (errAEEventNotPermitted) means Automation permission for Music.app
                // hasn't been granted — logged distinctly so a track that simply has no
                // artwork isn't confused with a permission outage affecting every track.
                let code = error[NSAppleScript.errorNumber] as? Int ?? 0
                logger.debug(
                    "fetchAppleMusicArtworkData failed [\(code)]: \(error[NSAppleScript.errorMessage] as? String ?? "unknown")"
                )
                return nil
            }
            guard let data = result?.data, !data.isEmpty else {
                logger.debug("fetchAppleMusicArtworkData: no artwork data on current track")
                return nil
            }
            return data
        }.value
    }

    // MARK: - YouTube Music

    /// Fetches artwork data via direct thumbnail URL (from JS injection) or falls back to iTunes Search API.
    func fetchYouTubeMusicArtworkData(thumbnailURL: URL? = nil, title: String, artist: String) async -> Data? {
        // Direct thumbnail URL — accurate and fast
        if let url = thumbnailURL,
            let data = try? await URLSession.shared.data(from: url).0,
            NSImage(data: data) != nil
        {
            return data
        }

        // iTunes Search API fallback
        let query =
            "\(title) \(artist)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let searchURL = URL(string: "https://itunes.apple.com/search?term=\(query)&entity=song&limit=5") else {
            return nil
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: searchURL)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let results = json["results"] as? [[String: Any]]
            else { return nil }
            // Pick best match: prefer result whose trackName contains the searched title
            let normalizedTitle = title.lowercased()
            let match =
                results.first(where: {
                    ($0["trackName"] as? String)?.lowercased().contains(normalizedTitle) == true
                }) ?? results.first
            guard let artworkStr = match?["artworkUrl100"] as? String else { return nil }
            let hiRes = artworkStr.replacingOccurrences(of: "100x100bb", with: "300x300bb")
            guard let artURL = URL(string: hiRes) else { return nil }
            let (artData, _) = try await URLSession.shared.data(from: artURL)
            return NSImage(data: artData) == nil ? nil : artData
        } catch {
            return nil
        }
    }

    // MARK: - Private

    private func runAppleScript(_ source: String) async -> String? {
        let logger = logger
        return await Task.detached {
            var error: NSDictionary?
            let script = NSAppleScript(source: source)
            let result = script?.executeAndReturnError(&error)
            if let error {
                let code = error[NSAppleScript.errorNumber] as? Int ?? 0
                logger.debug(
                    "runAppleScript failed [\(code)]: \(error[NSAppleScript.errorMessage] as? String ?? "unknown")"
                )
                return nil
            }
            return result?.stringValue
        }.value
    }
}
