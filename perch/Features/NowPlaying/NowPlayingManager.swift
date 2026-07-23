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
        ("org.mozilla.firefox", "Firefox"),
        ("org.mozilla.firefoxdeveloperedition", "Firefox Developer Edition"),
        ("org.mozilla.nightly", "Firefox Nightly"),
        ("app.zen-browser.zen", "Zen"),
        ("com.apple.Safari", "Safari"),
        ("company.thebrowser.dia", "Dia"),
    ]
    private(set) var currentState: NowPlayingState?
    let audioCaptureService = AudioCaptureService()

    // nonisolated(unsafe): written on MainActor (setup), read in deinit (nonisolated context).
    // @Observable macro expansion requires nonisolated(unsafe) — plain nonisolated is rejected
    // for mutable stored properties. The "no effect" compiler warning is cosmetic; the keyword
    // is still required to suppress the MainActor-isolation error in deinit.
    // Safety: no concurrent writes; deinit read is single-threaded on dealloc.
    private nonisolated(unsafe) var ncObservers: [NSObjectProtocol] = []  // NotificationCenter.default
    private nonisolated(unsafe) var dnObservers: [NSObjectProtocol] = []  // DistributedNotificationCenter
    private nonisolated(unsafe) var wsObservers: [NSObjectProtocol] = []  // NSWorkspace.shared.notificationCenter
    // nonisolated(unsafe): accessed from deinit. cancel() on Task is Sendable — safe from any context.
    private nonisolated(unsafe) var ytmPollTask: Task<Void, Never>?
    private nonisolated(unsafe) var amPositionTask: Task<Void, Never>?
    private nonisolated(unsafe) var lyricsPrefetchTask: Task<Void, Never>?
    private nonisolated(unsafe) var mediaRemoteStateTask: Task<Void, Never>?
    private var isYTMPolling: Bool = false
    private var wasYTMPolling: Bool = false
    /// Cap on how many times `pollAppleMusicPosition` will retry Apple Music
    /// artwork per track. Prevents infinite polling loops when both the
    /// AppleScript path AND iTunes Search fallback fail (e.g. offline, or the
    /// track isn't in iTunes' catalog). Reset on every track change.
    private var appleMusicArtworkPollAttempts: Int = 0
    private static let appleMusicArtworkPollAttemptLimit: Int = 3
    private let logger = Logger(label: "com.tukuyomi032.perch.NowPlayingManager")

    init() {
        setupSpotifyObserver()
        setupAppleMusicObserver()
        setupLifecycleObservers()
        startYouTubeMusicPolling()
        Task { @MainActor in await attemptMRFetch() }
        // Only accept MediaRemote events from Chromium browsers (YTM source)
        let chromiumBundleIds = Set(Self.chromiumBrowsers.map(\.bundleId))
        MediaRemoteBridge.shared.bundleIdentifierFilter = { bundleId in
            guard let bundleId else { return false }
            guard chromiumBundleIds.contains(bundleId) else { return false }
            return NSWorkspace.shared.runningApplications.contains { app in
                app.bundleIdentifier == bundleId
            }
        }
        MediaRemoteBridge.shared.start()
        mediaRemoteStateTask = Task { [weak self] in
            for await state in MediaRemoteBridge.shared.stateUpdates {
                guard let self else { return }
                await MainActor.run {
                    guard self.isYTMPolling else { return }
                    if let current = self.currentState,
                        current.isPlaying,
                        Self.sourcePriority(current.source.rawValue) >= Self.sourcePriority("Spotify")
                    {
                        return
                    }
                    self.applyState(state, source: "YouTube Music")
                }
            }
        }
    }

    deinit {
        ncObservers.forEach { NotificationCenter.default.removeObserver($0) }
        dnObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        wsObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        ytmPollTask?.cancel()
        amPositionTask?.cancel()
        lyricsPrefetchTask?.cancel()
        mediaRemoteStateTask?.cancel()
        Task { @MainActor in MediaRemoteBridge.shared.stop() }
    }

    // MARK: - Playback Controls

    func togglePlayPause() {
        switch currentState?.source {
        case .spotify:
            Task { @MainActor [weak self] in _ = await self?.runAppleScript("tell application \"Spotify\" to playpause")
            }
        case .appleMusic:
            Task { @MainActor [weak self] in _ = await self?.runAppleScript("tell application \"Music\" to playpause") }
        case .youTubeMusic where isYTMPolling:
            MediaRemoteBridge.shared.togglePlayPause()
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
        case .youTubeMusic where isYTMPolling:
            MediaRemoteBridge.shared.nextTrack()
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
        case .youTubeMusic where isYTMPolling:
            MediaRemoteBridge.shared.seek(to: seconds)
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
        case .youTubeMusic where isYTMPolling:
            MediaRemoteBridge.shared.previousTrack()
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
            Task { @MainActor [weak self] in
                if playerState == "Stopped" {
                    self?.applyState(nil, source: "Spotify")
                    return
                }
                // Primary: Track ID prefix. Fallback: empty Name field (ads always omit Name).
                // trackNumber/Popularity are unreliable — newer Spotify may omit them.
                let isAdByTrackId = trackId?.hasPrefix("spotify:ad:") == true
                let isAdByFields = name.isEmpty && playerState == "Playing"
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
                guard let playerState else { return }
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
            Task { @MainActor [weak self] in
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

    // MARK: - Lifecycle Observers (app termination, sleep/wake)

    private func setupLifecycleObservers() {
        let ws = NSWorkspace.shared.notificationCenter

        let terminateObs = ws.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                let bundleID = app.bundleIdentifier
            else { return }
            Task { @MainActor [weak self] in self?.handleAppTermination(bundleID: bundleID) }
        }

        let sleepObs = ws.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.currentState = nil }
        }

        let wakeObs = ws.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.pollYouTubeMusic()
                let info = await MRMediaRemote.shared.fetchNowPlayingInfo()
                if let state = NowPlayingState(from: info) {
                    self.applyState(state, source: "MRMediaRemote")
                }
            }
        }

        wsObservers = [terminateObs, sleepObs, wakeObs]
    }

    private func handleAppTermination(bundleID: String) {
        guard let state = currentState else { return }
        let matches: Bool
        switch state.source {
        case .spotify: matches = bundleID == "com.spotify.client"
        case .appleMusic: matches = bundleID == "com.apple.Music"
        case .youTubeMusic: matches = Self.chromiumBrowsers.contains { $0.bundleId == bundleID }
        default: matches = false
        }
        if matches { currentState = nil }
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
        let nowPolling = !activeBrowsers.isEmpty
        // Browser(s) just quit → clear YTM state immediately
        if wasYTMPolling && !nowPolling && currentState?.source == .youTubeMusic {
            currentState = nil
        }
        wasYTMPolling = nowPolling
        isYTMPolling = nowPolling
        // State updates are handled exclusively by MediaRemoteBridge
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

        // Piggyback artwork retry: if the initial retry chain exhausted and we
        // still have no artwork for this track, quietly try again on each poll
        // — but only up to appleMusicArtworkPollAttemptLimit to avoid an
        // infinite loop when both AppleScript and iTunes Search miss.
        if state.artwork == nil,
            appleMusicArtworkPollAttempts < Self.appleMusicArtworkPollAttemptLimit
        {
            appleMusicArtworkPollAttempts += 1
            _ = await tryFetchAppleMusicArtwork(for: state)
        }

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

    // MARK: - Audio Capture

    private var ytmBrowserBundleId: String? {
        NSWorkspace.shared.runningApplications.first { app in
            Self.chromiumBrowsers.contains { $0.bundleId == (app.bundleIdentifier ?? "") }
        }?.bundleIdentifier
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
        if let incoming = newState, let current = currentState, current.isPlaying {
            guard Self.sourcePriority(incoming.source.rawValue) >= Self.sourcePriority(current.source.rawValue) else {
                return
            }
        }
        // Capture previous track identity before overwriting currentState.
        let prevTitle = currentState?.title
        let prevArtist = currentState?.artist
        let prevThumbnailURL = currentState?.thumbnailURL
        let trackIdentityChanged: Bool
        if let new = newState {
            trackIdentityChanged = prevTitle != new.title || prevArtist != new.artist
        } else {
            trackIdentityChanged = false
        }
        // Reset the Apple Music artwork-poll retry counter whenever the track
        // changes so a new song starts with a fresh N-attempt budget.
        if trackIdentityChanged {
            appleMusicArtworkPollAttempts = 0
        }
        // Carry forward previous artwork during track transitions (same source).
        // Prevents the music-note placeholder from flashing until new artwork is fetched.
        // Skip carry-forward during ads so the megaphone placeholder shows immediately.
        var stateToApply = newState
        if let new = newState, new.artwork == nil, !new.isAd,
            let old = currentState, old.artwork != nil,
            new.source == old.source,
            !(trackIdentityChanged && (new.source == .spotify || new.source == .appleMusic))
        {
            stateToApply = NowPlayingState(
                title: new.title, artist: new.artist, album: new.album, artwork: old.artwork,
                artworkID: old.artworkID,
                thumbnailURL: new.thumbnailURL,
                isPlaying: new.isPlaying, duration: new.duration,
                elapsedTime: new.elapsedTime, timestamp: new.timestamp, source: new.source
            )
        }
        if stateToApply == currentState {
            // Same state — normally we'd early-return, but if this is an Apple
            // Music track that never got its artwork, use this notification as
            // a re-fetch opportunity (the initial retry chain may have finished
            // before Music.app had the descriptor ready).
            if let current = currentState,
                current.source == .appleMusic,
                current.artwork == nil,
                current.isPlaying
            {
                Task { @MainActor [weak self] in
                    await self?.fetchAppleMusicArtworkWithRetry(for: current)
                }
            }
            return
        }
        currentState = stateToApply
        logger.debug("Now playing updated [\(source)]: \(stateToApply?.title ?? "nil")")
        let captureBundleId: String?
        switch stateToApply?.source {
        case .spotify: captureBundleId = "com.spotify.client"
        case .appleMusic: captureBundleId = "com.apple.Music"
        case .youTubeMusic: captureBundleId = ytmBrowserBundleId
        default: captureBundleId = nil
        }
        if let bid = captureBundleId {
            Task { await audioCaptureService.startCapturing(bundleId: bid) }
        } else {
            Task { await audioCaptureService.stopCapturing() }
        }
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
        // For YTM, always refetch artwork when the track changes (title/thumbnailURL differs),
        // even if carry-forward populated state.artwork with the previous song's image.
        // For other sources, only fetch when artwork is missing.
        let needsFetch: Bool
        switch state.source {
        case .youTubeMusic:
            needsFetch =
                state.artwork == nil
                || prevTitle != state.title
                || prevArtist != state.artist
                || prevThumbnailURL != state.thumbnailURL
        case .spotify, .appleMusic:
            needsFetch =
                state.artwork == nil
                || prevTitle != state.title
                || prevArtist != state.artist
        default:
            needsFetch = state.artwork == nil
        }
        if needsFetch {
            Task { @MainActor [weak self] in
                await self?.fetchAndApplyArtwork(for: state)
            }
        }
        if state.source != .mrMediaRemote, !state.isAd {
            lyricsPrefetchTask?.cancel()
            lyricsPrefetchTask = Task {
                _ = await LyricsStore.shared.fetchLyrics(
                    title: state.title,
                    artist: state.artist,
                    album: state.album,
                    duration: state.duration
                )
            }
        }
    }

    private func fetchAndApplyArtwork(for state: NowPlayingState) async {
        // Apple Music routes through a dedicated retry helper because the
        // initial AppleScript call can race Music.app's metadata population,
        // AND the AppleScript path may be permission-denied entirely. The
        // helper's fetcher includes an iTunes Search API fallback so a single
        // retry catches the network-flake case without infinite loops.
        if state.source == .appleMusic {
            await fetchAppleMusicArtworkWithRetry(for: state)
            return
        }

        let artworkData: Data?
        switch state.source {
        case .spotify:
            do {
                artworkData = try await ArtworkFetcher.shared.fetchSpotifyArtworkData()
            } catch {
                logger.warning(
                    "Spotify artwork fetch failed for '\(state.title)': \(String(describing: error))"
                )
                artworkData = nil
            }
        case .youTubeMusic:
            do {
                artworkData = try await ArtworkFetcher.shared.fetchYouTubeMusicArtworkData(
                    thumbnailURL: state.thumbnailURL,
                    title: state.title,
                    artist: state.artist
                )
            } catch {
                logger.warning(
                    "YouTube Music artwork fetch failed for '\(state.title)': \(String(describing: error))"
                )
                artworkData = nil
            }
        default:
            return
        }
        guard let artworkData, let artwork = NSImage(data: artworkData) else { return }
        guard currentState?.title == state.title,
            currentState?.artist == state.artist,
            currentState?.thumbnailURL == state.thumbnailURL,
            currentState?.source == state.source
        else { return }
        currentState = state.enriched(artwork: artwork)
    }

    /// Apple Music: initial fetch + one retry after 500ms. `ArtworkFetcher`
    /// falls back from AppleScript to iTunes Search API internally, so extra
    /// retries would only help for transient network failure — one is enough.
    /// Each attempt re-validates track identity so a fetch spawned for a
    /// previous song can't clobber a newer one.
    private func fetchAppleMusicArtworkWithRetry(for state: NowPlayingState) async {
        if await tryFetchAppleMusicArtwork(for: state) { return }
        try? await Task.sleep(for: .milliseconds(500))
        guard sameAppleMusicTrack(as: state), currentState?.artwork == nil else { return }
        _ = await tryFetchAppleMusicArtwork(for: state)
    }

    /// Returns true when artwork was fetched, validated, and applied. Callable
    /// both from the retry chain and from position-polling piggyback.
    @discardableResult
    private func tryFetchAppleMusicArtwork(for state: NowPlayingState) async -> Bool {
        let data: Data
        do {
            data = try await ArtworkFetcher.shared.fetchAppleMusicArtworkData(
                title: state.title,
                artist: state.artist,
                album: state.album
            ) { [logger] appleScriptError in
                // Log AppleScript failure even if the iTunes Search fallback succeeds
                // — this is how we discover TCC permission problems in the wild.
                logger.warning(
                    "Apple Music AppleScript failed (falling back to iTunes Search): \(String(describing: appleScriptError))"
                )
            }
        } catch {
            logger.warning(
                "Apple Music artwork fetch failed for '\(state.title)': \(String(describing: error))"
            )
            return false
        }
        guard let image = NSImage(data: data), sameAppleMusicTrack(as: state) else { return false }
        currentState = state.enriched(artwork: image)
        logger.debug("Apple Music artwork applied for '\(state.title)'")
        return true
    }

    private func sameAppleMusicTrack(as state: NowPlayingState) -> Bool {
        currentState?.source == .appleMusic
            && currentState?.title == state.title
            && currentState?.artist == state.artist
    }
}
