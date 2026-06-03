// perch/Features/NowPlaying/NowPlayingManager.swift
import AppKit
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
    }

    // MARK: - Playback Controls

    func togglePlayPause() { MRMediaRemote.shared.sendCommand(.togglePlayPause) }
    func nextTrack() { MRMediaRemote.shared.sendCommand(.nextTrack) }
    func previousTrack() { MRMediaRemote.shared.sendCommand(.previousTrack) }

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
            let name = info["Name"] as? String ?? info["Track Name"] as? String ?? ""
            let artist = info["Artist"] as? String ?? ""
            let album = info["Album"] as? String
            let durationMs = info["Duration"] as? Double
            let position = info["Playback Position"] as? Double
            MainActor.assumeIsolated { [weak self] in
                if playerState == "Stopped" {
                    self?.applyState(nil, source: "Spotify")
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
            let script = """
                tell application "\(browser.appName)"
                    if not running then return ""
                    if (count of windows) = 0 then return ""
                    repeat with w in windows
                        set t to title of active tab of w
                        if t contains "YouTube Music" then return t
                    end repeat
                    return ""
                end tell
                """
            if let title = await runAppleScript(script), !title.isEmpty {
                applyState(NowPlayingState(fromYouTubeMusicTitle: title), source: "YouTube Music")
                return
            }
        }
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
        guard let state = currentState, state.source == .appleMusic else { return }
        currentState = NowPlayingState(
            title: state.title, artist: state.artist, album: state.album, artwork: state.artwork,
            isPlaying: state.isPlaying, duration: state.duration,
            elapsedTime: position, timestamp: Date(), source: state.source
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

    // MARK: - State Application

    private func applyState(_ newState: NowPlayingState?, source: String) {
        guard newState != currentState else { return }
        currentState = newState
        logger.debug("Now playing updated [\(source)]: \(newState?.title ?? "nil")")
        guard let state = newState else {
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
    }

    private func fetchAndApplyArtwork(for state: NowPlayingState) async {
        let artwork: NSImage?
        switch state.source {
        case .spotify:
            artwork = await ArtworkFetcher.shared.fetchSpotifyArtwork()
        case .appleMusic:
            artwork = await ArtworkFetcher.shared.fetchAppleMusicArtwork()
        default:
            return
        }
        guard let artwork else { return }
        guard currentState == state else { return }
        currentState = state.enriched(artwork: artwork)
    }
}
