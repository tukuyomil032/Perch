// perch/Features/NowPlaying/NowPlayingManager.swift
import AppKit
import Defaults
import Foundation
import Logging
import MediaRemoteAdapter

@Observable
@MainActor
final class NowPlayingManager {
    // "Applications" (not "Browsers") because this also matches native YTM clients like Kaset,
    // which publish Now Playing via MPNowPlayingInfoCenter/MPRemoteCommandCenter — the same
    // MediaRemote pipeline as a Chromium tab playing music.youtube.com.
    private static let youtubeMusicApplications: [(bundleId: String, appName: String)] = [
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
        ("com.sertacozercan.Kaset", "Kaset"),
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
    private let logger: Logger = {
        var logger = Logger(label: "com.tukuyomi032.perch.NowPlayingManager")
        logger.logLevel = .debug
        return logger
    }()

    init() {
        setupSpotifyObserver()
        setupAppleMusicObserver()
        setupLifecycleObservers()
        startYouTubeMusicPolling()
        Task { @MainActor in await attemptMRFetch() }
        // Only accept MediaRemote events from known YTM-producing applications (browsers + Kaset).
        MediaRemoteBridge.shared.bundleIdentifierResolver = { [logger] payload in
            let runningBundleIdentifiers = Set(
                NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
            )
            let resolved = Self.resolveBundleIdentifier(
                bundleId: payload.bundleIdentifier,
                applicationName: payload.applicationName,
                runningBundleIdentifiers: runningBundleIdentifiers
            )
            if let resolved {
                logger.debug("bundleIdentifierResolver: accepted, resolved to \(resolved)")
            } else {
                logger.debug(
                    "bundleIdentifierResolver: rejected bundleId=\(payload.bundleIdentifier ?? "nil") applicationName=\(payload.applicationName ?? "nil")"
                )
            }
            return resolved
        }
        MediaRemoteBridge.shared.start()
        mediaRemoteStateTask = Task { [weak self] in
            for await state in MediaRemoteBridge.shared.stateUpdates {
                guard let self else { return }
                await MainActor.run {
                    self.logger.debug(
                        "MediaRemoteBridge state received: title=\(state?.title ?? "nil") bundleId=\(state?.sourceBundleIdentifier ?? "nil") isYTMPolling=\(self.isYTMPolling)"
                    )
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
        if Self.matchesTerminatedApp(
            bundleID: bundleID,
            source: state.source,
            sourceBundleIdentifier: state.sourceBundleIdentifier
        ) {
            currentState = nil
        }
    }

    /// Whether the terminated app (`bundleID`) is the one currently backing `source`.
    /// For `.youTubeMusic`, prefers the exact bundle id the active state was sourced from
    /// (set by MediaRemoteBridge) over list-membership — with multiple YTM-producing apps
    /// (e.g. a browser AND Kaset) running simultaneously, list-membership alone would clear
    /// the active state when an unrelated one of them quits. Falls back to list-membership
    /// only when the state predates bundle-id tracking (e.g. AppleScript/JS-derived sources).
    static func matchesTerminatedApp(
        bundleID: String, source: MusicSource, sourceBundleIdentifier: String?
    ) -> Bool {
        switch source {
        case .spotify: return bundleID == "com.spotify.client"
        case .appleMusic: return bundleID == "com.apple.Music"
        case .youTubeMusic:
            if let sourceBundleIdentifier {
                return sourceBundleIdentifier == bundleID
            }
            return youtubeMusicApplications.contains { $0.bundleId == bundleID }
        case .mrMediaRemote:
            return false
        }
    }

    /// Decides which bundle id (if any) a raw MediaRemote payload should be attributed to.
    /// Returns nil to reject the event entirely.
    ///
    /// Most apps report their own bundle id directly and just need a running-app + allow-list
    /// check. Kaset is the exception: it hands off its real playing-state metadata to an
    /// embedded WebKit helper process while actively playing (bundleIdentifier
    /// "com.apple.WebKit.*", shared system-wide across every app that uses WKWebView), so for
    /// that prefix the only way to tell "Kaset's WebKit" from e.g. "Safari's WebKit" is
    /// `applicationName` — matched against the known apps' display names and remapped back to
    /// that app's own bundle id.
    static func resolveBundleIdentifier(
        bundleId: String?, applicationName: String?, runningBundleIdentifiers: Set<String>
    ) -> String? {
        guard let bundleId else { return nil }
        if bundleId.hasPrefix("com.apple.WebKit.") {
            guard let applicationName,
                let hosted = youtubeMusicApplications.first(where: { applicationName.hasPrefix($0.appName) })
            else { return nil }
            return hosted.bundleId
        }
        guard youtubeMusicApplications.contains(where: { $0.bundleId == bundleId }) else { return nil }
        return runningBundleIdentifiers.contains(bundleId) ? bundleId : nil
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
        let activeApplications = Self.youtubeMusicApplications.filter { runningIds.contains($0.bundleId) }
        let nowPolling = !activeApplications.isEmpty
        // Browser(s) just quit → clear YTM state immediately
        if wasYTMPolling && !nowPolling && currentState?.source == .youTubeMusic {
            currentState = nil
        }
        if nowPolling != isYTMPolling {
            logger.debug(
                "isYTMPolling \(isYTMPolling) -> \(nowPolling), active: \(activeApplications.map(\.appName))"
            )
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
                sourceBundleIdentifier: new.sourceBundleIdentifier,
                isPlaying: new.isPlaying, duration: new.duration,
                elapsedTime: new.elapsedTime, timestamp: new.timestamp, source: new.source
            )
        }
        guard stateToApply != currentState else { return }
        currentState = stateToApply
        logger.debug("Now playing updated [\(source)]: \(stateToApply?.title ?? "nil")")
        let captureBundleId: String?
        switch stateToApply?.source {
        case .spotify: captureBundleId = "com.spotify.client"
        case .appleMusic: captureBundleId = "com.apple.Music"
        case .youTubeMusic: captureBundleId = stateToApply?.sourceBundleIdentifier
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
                    album: state.album
                )
            }
        }
    }

    private func fetchAndApplyArtwork(for state: NowPlayingState) async {
        let artworkData: Data?
        switch state.source {
        case .spotify:
            artworkData = await ArtworkFetcher.shared.fetchSpotifyArtworkData()
        case .appleMusic:
            artworkData = await ArtworkFetcher.shared.fetchAppleMusicArtworkData()
        case .youTubeMusic:
            // Always fetch fresh artwork for YTM — carry-forward may have populated
            // state.artwork with the previous song's image, so guard state.artwork == nil
            // was previously blocking refetch on track change. applyState now gates the
            // call via needsFetch, so we unconditionally fetch here.
            artworkData = await ArtworkFetcher.shared.fetchYouTubeMusicArtworkData(
                thumbnailURL: state.thumbnailURL,
                title: state.title,
                artist: state.artist
            )
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
}
