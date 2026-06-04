// perch/Features/NowPlaying/ArtworkFetcher.swift
import AppKit
import Foundation

/// Fetches album artwork via AppleScript for Spotify and Apple Music.
/// `actor` isolation serializes fetches so NSAppleScript is never called concurrently.
actor ArtworkFetcher {
    static let shared = ArtworkFetcher()
    private init() {}

    private var lastSpotifyURL: String = ""

    // MARK: - Spotify

    /// Returns artwork by fetching the track's artwork URL via AppleScript, then downloading it.
    func fetchSpotifyArtwork() async -> NSImage? {
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
        lastSpotifyURL = urlString
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return NSImage(data: data)
        } catch {
            return nil
        }
    }

    // MARK: - Apple Music

    /// Returns artwork by reading binary image data directly from the AppleScript descriptor.
    func fetchAppleMusicArtwork() async -> NSImage? {
        await Task.detached {
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
            guard let result = script?.executeAndReturnError(&error), error == nil else { return nil }
            let data = result.data
            guard !data.isEmpty else { return nil }
            return NSImage(data: data)
        }.value
    }

    // MARK: - YouTube Music

    /// Fetches artwork via direct thumbnail URL (from JS injection) or falls back to iTunes Search API.
    func fetchYouTubeMusicArtwork(thumbnailURL: URL? = nil, title: String, artist: String) async -> NSImage? {
        // Direct thumbnail URL — accurate and fast
        if let url = thumbnailURL,
            let data = try? await URLSession.shared.data(from: url).0,
            let image = NSImage(data: data)
        {
            return image
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
            return NSImage(data: artData)
        } catch {
            return nil
        }
    }

    // MARK: - Private

    private func runAppleScript(_ source: String) async -> String? {
        await Task.detached {
            var error: NSDictionary?
            let script = NSAppleScript(source: source)
            let result = script?.executeAndReturnError(&error)
            guard error == nil else { return nil }
            return result?.stringValue
        }.value
    }
}
