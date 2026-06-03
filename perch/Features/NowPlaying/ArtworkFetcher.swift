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
