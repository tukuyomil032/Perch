// perch/Features/NowPlaying/NowPlayingManager.swift
import AppKit
import Defaults
import Foundation
import Logging

@Observable
@MainActor
final class NowPlayingManager {
    private static let chromiumBrowsers: [(bundleId: String, appName: String)] = [
        ("com.google.Chrome", "Google Chrome"),
        ("com.google.Chrome.beta", "Google Chrome Beta"),
        ("com.google.Chrome.canary", "Google Chrome Canary"),
        ("company.thebrowser.Browser", "Arc"),
        ("com.brave.Browser", "Brave Browser"),
        ("com.microsoft.edgemac", "Microsoft Edge"),
        ("com.operasoftware.Opera", "Opera"),
        ("com.vivaldi.Vivaldi", "Vivaldi"),
        ("com.pushplaylabs.sidekick", "Sidekick"),
    ]
    private(set) var currentState: NowPlayingState?

    // nonisolated(unsafe): written on MainActor (setup), read in deinit (nonisolated context).
    // @Observable macro expansion requires nonisolated(unsafe) — plain nonisolated is rejected
    // for mutable stored properties. The "no effect" compiler warning is cosmetic; the keyword
    // is still required to suppress the MainActor-isolation error in deinit.
    // Safety: no concurrent writes; deinit read is single-threaded on dealloc.
    private nonisolated(unsafe) var ncObservers: [NSObjectProtocol] = []  // NotificationCenter.default
    private nonisolated(unsafe) var dnObservers: [NSObjectProtocol] = []  // DistributedNotificationCenter
    // nonisolated(unsafe): accessed from deinit. cancel() on Task is Sendable — safe from any context.
    private nonisolated(unsafe) var ytmPollTask: Task<Void, Never>?
    private nonisolated(unsafe) var amPositionTask: Task<Void, Never>?
    private nonisolated(unsafe) var lyricsPrefetchTask: Task<Void, Never>?
    private let logger = Logger(label: "com.tukuyomi032.perch.NowPlayingManager")

    init() {
        setupSpotifyObserver()
        setupAppleMusicObserver()
        startYouTubeMusicPolling()
        Task { @MainActor in await attemptMRFetch() }
    }

    deinit {
        ncObservers.forEach { NotificationCenter.default.removeObserver($0) }
        dnObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        ytmPollTask?.cancel()
        amPositionTask?.cancel()
        lyricsPrefetchTask?.cancel()
    }

    // MARK: - Playback Controls

    func togglePlayPause() {
        switch currentState?.source {
        case .spotify:
            Task { @MainActor [weak self] in _ = await self?.runAppleScript("tell application \"Spotify\" to playpause")
            }
        case .appleMusic:
            Task { @MainActor [weak self] in _ = await self?.runAppleScript("tell application \"Music\" to playpause") }
        default:
            MRMediaRemote.shared.sendCommand(.togglePlayPause)
        }
    }

    func nextTrack() {
        switch currentState?.source {
        case .spotify:
            Task { @MainActor [weak self] in
                _ = await self?.runAppleScript("tell application \"Spotify\" to next track")
            }
        case .appleMusic:
            Task { @MainActor [weak self] in _ = await self?.runAppleScript("tell application \"Music\" to next track")
            }
        default:
            MRMediaRemote.shared.sendCommand(.nextTrack)
        }
    }

    func seek(to seconds: TimeInterval) {
        switch currentState?.source {
        case .appleMusic:
            Task { @MainActor [weak self] in
                _ = await self?.runAppleScript(
                    "tell application \"Music\" to set player position to \(seconds)")
            }
        case .spotify:
            Task { @MainActor [weak self] in
                _ = await self?.runAppleScript(
                    "tell application \"Spotify\" to set player position to \(seconds)")
            }
        default:
            break
        }
    }

    func previousTrack() {
        switch currentState?.source {
        case .spotify:
            Task { @MainActor [weak self] in
                _ = await self?.runAppleScript("tell application \"Spotify\" to previous track")
            }
        case .appleMusic:
            Task { @MainActor [weak self] in
                _ = await self?.runAppleScript("tell application \"Music\" to previous track")
            }
        default:
            MRMediaRemote.shared.sendCommand(.previousTrack)
        }
    }

    // MARK: - Spotify (DistributedNotificationCenter)

    private func setupSpotifyObserver() {
        // `queue: .main` ensures this closure runs on the main thread.
        // We extract only Sendable scalar values from userInfo before calling any
        // @MainActor-isolated code, avoiding "sending non-Sendable" Swift 6 errors.
        let observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let info = notification.userInfo else { return }
            let playerState = info["Player State"] as? String
            let trackId = info["Track ID"] as? String
            let name = info["Name"] as? String ?? info["Track Name"] as? String ?? ""
            let artist = info["Artist"] as? String ?? ""
            let album = info["Album"] as? String
            let durationMs = info["Duration"] as? Double
            let position = info["Playback Position"] as? Double
            let trackNumber = info["Track Number"] as? Int
            let popularity = info["Popularity"] as? Int
            MainActor.assumeIsolated { [weak self] in
                if playerState == "Stopped" {
                    self?.applyState(nil, source: "Spotify")
                    return
                }
                // Primary: Track ID prefix. Fallback: Track Number=0 + Popularity=0
                // (confirmed by Spotifree, citruspi/Spotify-Notifications via reverse-engineering
                //  of com.spotify.client.PlaybackStateChanged payload)
                let isAdByTrackId = trackId?.hasPrefix("spotify:ad:") == true
                let isAdByFields =
                    trackNumber == 0 && (popularity == nil || popularity == 0) && playerState == "Playing"
                if isAdByTrackId || isAdByFields {
                    let adState = NowPlayingState(
                        title: "Spotify Ad", artist: "", album: nil, artwork: nil,
                        artworkID: nil, thumbnailURL: nil, isAd: true,
                        isPlaying: playerState == "Playing",
                        duration: durationMs.map { $0 / 1000.0 },
                        elapsedTime: position,
                        timestamp: Date(), source: .spotify
                    )
                    self?.applyState(adState, source: "Spotify")
                    return
                }
                guard let playerState, !name.isEmpty else { return }
                let state = NowPlayingState(
                    spotifyPlayerState: playerState, title: name, artist: artist, album: album,
                    durationMs: durationMs, position: position
                )
                self?.applyState(state, source: "Spotify")
            }
        }
        dnObservers.append(observer)
    }

    // MARK: - Apple Music (DistributedNotificationCenter)

    private func setupAppleMusicObserver() {
        let observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let info = notification.userInfo else { return }
            let playerState = info["Player State"] as? String
            let name = info["Name"] as? String ?? ""
            let artist = info["Artist"] as? String ?? ""
            let album = info["Album"] as? String
            let totalTime = info["Total Time"] as? Double
            MainActor.assumeIsolated { [weak self] in
                if playerState == "Stopped" {
                    self?.applyState(nil, source: "Apple Music")
                    return
                }
                guard let playerState else { return }
                let state = NowPlayingState(
                    appleMusicPlayerState: playerState, title: name, artist: artist, album: album,
                    totalTime: totalTime
                )
                self?.applyState(state, source: "Apple Music")
            }
        }
        dnObservers.append(observer)
    }

    // MARK: - YouTube Music (AppleScript polling)

    private func startYouTubeMusicPolling() {
        ytmPollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollYouTubeMusic()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func pollYouTubeMusic() async {
        let runningIds = Set(
            NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }
        )
        let activeBrowsers = Self.chromiumBrowsers.filter { runningIds.contains($0.bundleId) }
        for browser in activeBrowsers {
            // JS injection: get structured data (title, artist, thumbnail, playing state)
            if let state = await pollYouTubeMusicJS(browser: browser) {
                applyState(state, source: "YouTube Music")
                return
            }
            // Fallback: tab title parsing
            let titleScript = """
                tell application "\(browser.appName)"
                    if not running then return ""
                    if (count of windows) = 0 then return ""
                    repeat with w in windows
                        repeat with t in tabs of w
                            if title of t contains "YouTube Music" then return title of t
                        end repeat
                    end repeat
                    return ""
                end tell
                """
            if let title = await runAppleScript(titleScript), !title.isEmpty,
                let state = NowPlayingState(fromYouTubeMusicTitle: title)
            {
                applyState(state, source: "YouTube Music")
                return
            }
        }
    }

    private func pollYouTubeMusicJS(browser: (bundleId: String, appName: String)) async -> NowPlayingState? {
        // Verified selectors (from DOM inspection of multiple open-source YTM projects):
        //   title:     yt-formatted-string.title.style-scope.ytmusic-player-bar
        //   artist:    .byline.ytmusic-player-bar > yt-formatted-string
        //   thumbnail: #song-image img
        //   playing:   video.paused (locale-independent)
        let jsPayload =
            "(function(){try{"
            + "var t=document.querySelector('yt-formatted-string.title.style-scope.ytmusic-player-bar');"
            + "if(!t||!t.textContent.trim())return 'null';"
            + "var a=document.querySelector('.byline.ytmusic-player-bar>yt-formatted-string')"
            + "||document.querySelector('.byline.ytmusic-player-bar');"
            + "var img=document.querySelector('#song-image img')"
            + "||document.querySelector('.ytmusic-player-bar img');"
            + "var v=document.querySelector('video');"
            + "var playing=v?!v.paused:true;"
            + "return JSON.stringify({"
            + "title:t.textContent.trim(),"
            + "artist:a?a.textContent.trim():'',"
            + "thumbnail:img?img.src:'',"
            + "playing:playing"
            + "});"
            + "}catch(e){return 'null';}})()"

        // Escape double-quotes for AppleScript string embedding
        let escapedJS = jsPayload.replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
            tell application "\(browser.appName)"
                if not running then return ""
                if (count of windows) = 0 then return ""
                repeat with w in windows
                    repeat with t in tabs of w
                        if URL of t contains "music.youtube.com" then
                            try
                                set res to execute t javascript "\(escapedJS)"
                                if res is not "" and res is not "null" then return res
                            end try
                        end if
                    end repeat
                end repeat
                return ""
            end tell
            """
        guard let json = await runAppleScript(script),
            !json.isEmpty, json != "null"
        else { return nil }
        return NowPlayingState(fromYouTubeMusicJS: json)
    }

    private func runAppleScript(_ source: String) async -> String? {
        await Task.detached {
            var error: NSDictionary?
            let script = NSAppleScript(source: source)
            let result = script?.executeAndReturnError(&error)
            guard error == nil else { return nil }
            return result?.stringValue
        }.value
    }

    // MARK: - Apple Music Position Polling

    private func startAppleMusicPositionPolling() {
        amPositionTask?.cancel()
        amPositionTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollAppleMusicPosition()
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    private func pollAppleMusicPosition() async {
        // Capture title before the await — prevents stale position from a previous song
        // being applied to a newly started song (race condition).
        guard let state = currentState, state.source == .appleMusic else { return }
        let capturedTitle = state.title

        let script = """
            tell application "Music"
                if not running then return "-1"
                if player state is stopped then return "-1"
                return player position as string
            end tell
            """
        guard let result = await runAppleScript(script),
            let position = Double(result), position >= 0
        else { return }

        // Verify the track hasn't changed while we were awaiting the AppleScript result.
        guard let current = currentState,
            current.source == .appleMusic,
            current.title == capturedTitle
        else { return }

        // Skip if position matches or exceeds duration (end-of-track artifact from previous song).
        if let dur = current.duration, position >= dur { return }

        currentState = NowPlayingState(
            title: current.title, artist: current.artist, album: current.album,
            artwork: current.artwork,
            artworkID: current.artworkID,
            thumbnailURL: current.thumbnailURL,
            isPlaying: current.isPlaying, duration: current.duration,
            elapsedTime: position, timestamp: Date(), source: current.source
        )
    }

    // MARK: - MRMediaRemote fallback
    // MRMediaRemote is registered on all versions but only produces results on macOS < 15.4.
    // Silently fails on macOS 15.4+.

    private func attemptMRFetch() async {
        let info = await MRMediaRemote.shared.fetchNowPlayingInfo()
        if let state = NowPlayingState(from: info) {
            applyState(state, source: "MRMediaRemote")
        }
        MRMediaRemote.shared.registerForNotifications()
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            .mrNowPlayingInfoDidChange,
            .mrNowPlayingApplicationIsPlayingDidChange,
        ]
        let mrObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    let info = await MRMediaRemote.shared.fetchNowPlayingInfo()
                    self?.applyState(NowPlayingState(from: info), source: "MRMediaRemote")
                }
            }
        }
        ncObservers.append(contentsOf: mrObservers)
    }

    // MARK: - Source Priority

    private static func sourcePriority(_ sourceName: String) -> Int {
        switch sourceName {
        case "Spotify": return 3
        case "Apple Music": return 3
        case "YouTube Music": return 2
        case "MRMediaRemote": return 1
        default: return 0
        }
    }

    // MARK: - State Application

    private func applyState(_ newState: NowPlayingState?, source: String) {
        // Respect per-source enable settings
        if let incoming = newState {
            switch incoming.source {
            case .spotify where !Defaults[.enableSpotify]: return
            case .appleMusic where !Defaults[.enableAppleMusic]: return
            case .youTubeMusic where !Defaults[.enableYouTubeMusic]: return
            default: break
            }
        }
        // Prevent lower-priority source from clearing higher-priority active state.
        // MRMediaRemote returning nil (blocked on macOS 16) must not override Spotify.
        if newState == nil, let current = currentState {
            guard Self.sourcePriority(source) >= Self.sourcePriority(current.source.rawValue) else { return }
        }
        // Carry forward previous artwork during track transitions (same source).
        // Prevents the music-note placeholder from flashing until new artwork is fetched.
        // Skip carry-forward during ads so the megaphone placeholder shows immediately.
        var stateToApply = newState
        if let new = newState, new.artwork == nil, !new.isAd,
            let old = currentState, old.artwork != nil,
            new.source == old.source
        {
            stateToApply = NowPlayingState(
                title: new.title, artist: new.artist, album: new.album, artwork: old.artwork,
                artworkID: old.artworkID,
                thumbnailURL: new.thumbnailURL,
                isPlaying: new.isPlaying, duration: new.duration,
                elapsedTime: new.elapsedTime, timestamp: new.timestamp, source: new.source
            )
        }
        guard stateToApply != currentState else { return }
        currentState = stateToApply
        logger.debug("Now playing updated [\(source)]: \(stateToApply?.title ?? "nil")")
        guard let state = stateToApply else {
            amPositionTask?.cancel()
            amPositionTask = nil
            return
        }
        if state.source == .appleMusic {
            startAppleMusicPositionPolling()
        } else {
            amPositionTask?.cancel()
            amPositionTask = nil
        }
        Task { @MainActor [weak self] in
            await self?.fetchAndApplyArtwork(for: state)
        }
        if state.source != .mrMediaRemote, !state.isAd {
            lyricsPrefetchTask?.cancel()
            lyricsPrefetchTask = Task {
                _ = await LyricsStore.shared.fetchLyrics(
                    title: state.title,
                    artist: state.artist,
                    album: state.album
                )
            }
        }
    }

    private func fetchAndApplyArtwork(for state: NowPlayingState) async {
        let artwork: NSImage?
        switch state.source {
        case .spotify:
            artwork = await ArtworkFetcher.shared.fetchSpotifyArtwork()
        case .appleMusic:
            artwork = await ArtworkFetcher.shared.fetchAppleMusicArtwork()
        case .youTubeMusic:
            artwork = await ArtworkFetcher.shared.fetchYouTubeMusicArtwork(
                thumbnailURL: state.thumbnailURL,
                title: state.title,
                artist: state.artist
            )
        default:
            return
        }
        guard let artwork else { return }
        guard currentState == state else { return }
        currentState = state.enriched(artwork: artwork)
    }
}
