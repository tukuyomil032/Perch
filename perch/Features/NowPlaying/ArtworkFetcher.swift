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

    // MARK: - YouTube Music (iTunes Search API)

    func fetchYouTubeMusicArtwork(title: String, artist: String) async -> NSImage? {
        let query =
            "\(artist) \(title)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://itunes.apple.com/search?term=\(query)&entity=song&limit=5") else {
            return nil
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let results = json["results"] as? [[String: Any]],
                let first = results.first,
                let artworkURLString = first["artworkUrl100"] as? String
            else { return nil }
            let hiResURL = artworkURLString.replacingOccurrences(of: "100x100bb", with: "300x300bb")
            guard let artworkURL = URL(string: hiResURL) else { return nil }
            let (artData, _) = try await URLSession.shared.data(from: artworkURL)
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
