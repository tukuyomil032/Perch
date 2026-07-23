// perch/Features/NowPlaying/ArtworkFetcher.swift
@preconcurrency import AppKit
import Foundation

/// Fetches album artwork for Spotify, Apple Music, and YouTube Music.
/// Actor isolation serializes AppleScript calls (NSAppleScript is not thread-safe).
actor ArtworkFetcher {
    static let shared = ArtworkFetcher()
    private init() {}

    private var lastSpotifyURL: String = ""

    // MARK: - Spotify

    /// AppleScript path → HTTP download. Throws so callers can log the failure
    /// reason (permission denied, HTTP failure, etc.) instead of guessing.
    func fetchSpotifyArtworkData() async throws -> Data {
        let urlString = try await runAppleScript(
            """
            tell application "Spotify"
                if not running then return ""
                return artwork url of current track as string
            end tell
            """)
        guard !urlString.isEmpty else { throw ArtworkFetchError.emptyData }
        // Dedup: skip re-downloading the same artwork within one session.
        guard urlString != lastSpotifyURL else { throw ArtworkFetchError.noResultsFound }
        guard let url = URL(string: urlString) else { throw ArtworkFetchError.decodeFailed }
        lastSpotifyURL = urlString
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return data
        } catch {
            throw ArtworkFetchError.httpFailed(underlying: error)
        }
    }

    // MARK: - Apple Music

    /// Apple Music artwork with iTunes Search fallback. AppleScript needs the
    /// user's Automation permission (macOS TCC) AND a locally cached artwork
    /// descriptor — neither is guaranteed for streaming-only catalog tracks.
    /// The iTunes Search API is a deterministic, HTTP-based backup.
    ///
    /// Throws only when BOTH paths fail. The last-thrown error surfaces so the
    /// caller can log why. First-path errors are logged via `onAppleScriptError`
    /// so a fallback success still records that AppleScript is misconfigured.
    func fetchAppleMusicArtworkData(
        title: String,
        artist: String,
        album: String?,
        onAppleScriptError: (@Sendable (ArtworkFetchError) -> Void)? = nil
    ) async throws -> Data {
        do {
            return try await fetchAppleMusicArtworkViaAppleScript()
        } catch let appleScriptError as ArtworkFetchError {
            onAppleScriptError?(appleScriptError)
        } catch {
            onAppleScriptError?(.scriptError(code: 0, message: String(describing: error)))
        }
        return try await fetchArtworkViaITunesSearch(title: title, artist: artist, album: album)
    }

    private func fetchAppleMusicArtworkViaAppleScript() async throws -> Data {
        try await Task.detached {
            guard
                let script = NSAppleScript(
                    source: """
                        tell application "Music"
                            if not running then return
                            if player state is stopped then return
                            return data of artwork 1 of current track
                        end tell
                        """)
            else {
                throw ArtworkFetchError.scriptCreationFailed
            }
            var errorDict: NSDictionary?
            let result = script.executeAndReturnError(&errorDict)
            if let err = errorDict {
                throw ArtworkFetchError(fromAppleScriptErrorDict: err)
            }
            let data = result.data
            guard !data.isEmpty else { throw ArtworkFetchError.emptyData }
            return data
        }.value
    }

    // MARK: - YouTube Music

    /// Direct thumbnail URL (from JS injection in the browser) → iTunes Search fallback.
    func fetchYouTubeMusicArtworkData(
        thumbnailURL: URL? = nil,
        title: String,
        artist: String
    ) async throws -> Data {
        if let url = thumbnailURL {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if NSImage(data: data) != nil { return data }
            } catch {
                // Fall through to iTunes Search API
            }
        }
        return try await fetchArtworkViaITunesSearch(title: title, artist: artist, album: nil)
    }

    // MARK: - iTunes Search API (shared)

    /// Queries `https://itunes.apple.com/search` for a track and returns the
    /// downloaded artwork bytes. Uses `artworkUrl100` from the response and
    /// upgrades the size to 600×600 (Apple's URL scheme allows this rewrite).
    func fetchArtworkViaITunesSearch(
        title: String,
        artist: String,
        album: String?
    ) async throws -> Data {
        let rawQuery: String
        if let album, !album.isEmpty {
            rawQuery = "\(title) \(artist) \(album)"
        } else {
            rawQuery = "\(title) \(artist)"
        }
        guard
            let encoded = rawQuery.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed),
            let searchURL = URL(
                string: "https://itunes.apple.com/search?term=\(encoded)&entity=song&limit=5")
        else {
            throw ArtworkFetchError.noResultsFound
        }

        let searchData: Data
        do {
            (searchData, _) = try await URLSession.shared.data(from: searchURL)
        } catch {
            throw ArtworkFetchError.httpFailed(underlying: error)
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: searchData) as? [String: Any],
            let results = json["results"] as? [[String: Any]],
            !results.isEmpty
        else {
            throw ArtworkFetchError.noResultsFound
        }

        // Prefer results whose trackName contains the searched title (case-insensitive)
        // to avoid picking a same-artist / different-song top hit.
        let normalizedTitle = title.lowercased()
        let bestMatch =
            results.first(where: {
                ($0["trackName"] as? String)?.lowercased().contains(normalizedTitle) == true
            }) ?? results[0]

        guard let artworkURL100 = bestMatch["artworkUrl100"] as? String else {
            throw ArtworkFetchError.noResultsFound
        }
        // Apple's iTunes artwork CDN accepts arbitrary size substitutions — use 600
        // for a crisp Dynamic Island thumbnail without pushing the transfer size too far.
        let hiRes = artworkURL100.replacingOccurrences(of: "100x100bb", with: "600x600bb")
        guard let artURL = URL(string: hiRes) else {
            throw ArtworkFetchError.decodeFailed
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: artURL)
            guard NSImage(data: data) != nil else { throw ArtworkFetchError.decodeFailed }
            return data
        } catch let error as ArtworkFetchError {
            throw error
        } catch {
            throw ArtworkFetchError.httpFailed(underlying: error)
        }
    }

    // MARK: - Private helpers

    private func runAppleScript(_ source: String) async throws -> String {
        try await Task.detached {
            guard let script = NSAppleScript(source: source) else {
                throw ArtworkFetchError.scriptCreationFailed
            }
            var errorDict: NSDictionary?
            let result = script.executeAndReturnError(&errorDict)
            if let err = errorDict {
                throw ArtworkFetchError(fromAppleScriptErrorDict: err)
            }
            return result.stringValue ?? ""
        }.value
    }
}

// MARK: - Error type

enum ArtworkFetchError: Error, CustomStringConvertible, Sendable {
    /// `NSAppleScript(source:)` returned nil — malformed script.
    case scriptCreationFailed
    /// TCC denied Apple Events (`errAEEventNotPermitted`, -1743). Info.plist
    /// needs `NSAppleEventsUsageDescription` AND the user must approve the
    /// Automation prompt in System Settings > Privacy & Security.
    case notPermitted
    /// AppleScript ran but the descriptor was empty (e.g. `if not running then
    /// return` fired). Not necessarily an error — the caller can try fallback.
    case emptyData
    /// `errAENoSuchObject` (-1728) — track/property doesn't exist.
    case noCurrentTrack
    /// Any other AppleScript error.
    case scriptError(code: Int, message: String)
    /// HTTP request failed.
    case httpFailed(underlying: Error)
    /// iTunes Search API returned no matching results.
    case noResultsFound
    /// Downloaded bytes weren't a decodable image.
    case decodeFailed

    init(fromAppleScriptErrorDict dict: NSDictionary) {
        let code = (dict["NSAppleScriptErrorNumber"] as? Int) ?? 0
        let message = (dict["NSAppleScriptErrorMessage"] as? String) ?? "unknown"
        switch code {
        case -1743: self = .notPermitted
        case -1728: self = .noCurrentTrack
        default: self = .scriptError(code: code, message: message)
        }
    }

    var description: String {
        switch self {
        case .scriptCreationFailed:
            return "NSAppleScript init returned nil"
        case .notPermitted:
            return
                "AppleScript not permitted (-1743) — check Automation permission for Perch in System Settings > Privacy & Security > Automation"
        case .emptyData:
            return "AppleScript returned no data (app not running or no artwork)"
        case .noCurrentTrack:
            return "No current track (-1728)"
        case .scriptError(let code, let message):
            return "AppleScript error \(code): \(message)"
        case .httpFailed(let underlying):
            return "HTTP request failed: \(underlying.localizedDescription)"
        case .noResultsFound:
            return "iTunes Search API returned no matching artwork"
        case .decodeFailed:
            return "Failed to decode artwork image data"
        }
    }
}
