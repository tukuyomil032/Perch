import Foundation
import Logging
import MediaRemoteAdapter

private let logger: Logger = {
    var logger = Logger(label: "com.tukuyomi032.perch.MediaRemoteBridge")
    logger.logLevel = .debug
    return logger
}()

@Observable
@MainActor
final class MediaRemoteBridge {
    static let shared = MediaRemoteBridge()

    private(set) var isListening = false
    /// Set by NowPlayingManager to restrict/remap events to specific apps (e.g. Chromium
    /// browsers). Takes the full payload (not just bundleIdentifier) and returns the bundle
    /// identifier the event should be attributed to, or nil to reject it. A resolved value can
    /// differ from `payload.bundleIdentifier` — e.g. Kaset publishes its real playing-state
    /// metadata from an embedded WebKit helper process (bundleIdentifier "com.apple.WebKit.*",
    /// shared system-wide across every app using WKWebView) rather than its own bundle id, so
    /// only `applicationName` distinguishes "Kaset's WebKit" from "Safari's WebKit" — the
    /// resolver remaps that case back to Kaset's own bundle id.
    var bundleIdentifierResolver: ((TrackInfo.Payload) -> String?)? = nil
    private(set) var currentState: NowPlayingState?

    // Same-track stabilization: prevents UUID churn causing artwork flicker
    private var lastTrackIdentifier: String? = nil
    private var lastArtworkID: UUID? = nil

    private nonisolated(unsafe) var stateContinuation: AsyncStream<NowPlayingState?>.Continuation?
    private(set) var stateUpdates: AsyncStream<NowPlayingState?>

    // nonisolated(unsafe): MediaController is not Sendable; control calls are safe via its internal commandQueue
    private nonisolated(unsafe) let controller = MediaController()

    private init() {
        var continuation: AsyncStream<NowPlayingState?>.Continuation?
        stateUpdates = AsyncStream { continuation = $0 }
        stateContinuation = continuation
    }

    // MARK: - Lifecycle

    func start() {
        guard !isListening else { return }

        controller.onTrackInfoReceived = { [weak self] trackInfo in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let trackInfo else {
                    // nil = nothing playing. Always propagate regardless of source filter —
                    // filter(nil) returns false, which would otherwise silently drop tab-close events.
                    self.lastTrackIdentifier = nil
                    self.lastArtworkID = nil
                    self.currentState = nil
                    self.stateContinuation?.yield(nil)
                    return
                }
                let payload = trackInfo.payload
                logger.debug(
                    "Raw MediaRemote event: bundleId=\(payload.bundleIdentifier ?? "nil") applicationName=\(payload.applicationName ?? "nil") PID=\(payload.PID.map(String.init) ?? "nil") title=\(payload.title ?? "nil")"
                )
                // Reject events not from an allowed application (e.g. non-Chromium apps), and
                // remap WebKit-helper events to the app that actually owns them.
                let resolvedBundleId: String?
                if let resolver = self.bundleIdentifierResolver {
                    resolvedBundleId = resolver(payload)
                    guard resolvedBundleId != nil else {
                        logger.debug(
                            "Rejected MediaRemote event from \(payload.bundleIdentifier ?? "nil") (not in allow-list)"
                        )
                        return
                    }
                } else {
                    resolvedBundleId = payload.bundleIdentifier
                }

                // Use title+artist only — album is unreliable in YTM MediaRemote updates
                let newIdentifier = "\(payload.title ?? "")-\(payload.artist ?? "")"
                let sameTrack =
                    self.lastTrackIdentifier != nil
                    && newIdentifier == self.lastTrackIdentifier

                // Reuse artworkID for same-track updates — prevents album art ↔ MV thumbnail animation
                let artworkID: UUID?
                if payload.artwork != nil {
                    artworkID = sameTrack ? (self.lastArtworkID ?? UUID()) : UUID()
                } else {
                    artworkID = nil
                }
                self.lastArtworkID = artworkID
                self.lastTrackIdentifier = newIdentifier

                // Carry forward elapsed time when partial update omits it (seek bar stability)
                let fallbackElapsed = sameTrack ? self.currentState?.elapsedTime : nil

                guard
                    let state = NowPlayingState(
                        fromMediaRemote: trackInfo,
                        overrideArtworkID: artworkID,
                        fallbackElapsedTime: fallbackElapsed,
                        overrideBundleIdentifier: resolvedBundleId
                    )
                else {
                    self.currentState = nil
                    self.stateContinuation?.yield(nil)
                    return
                }
                self.currentState = state
                self.stateContinuation?.yield(state)
            }
        }

        controller.onListenerTerminated = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                logger.warning("MediaRemote listener terminated unexpectedly")
                self.isListening = false
                self.currentState = nil
                self.stateContinuation?.yield(nil)
            }
        }

        controller.startListening()
        isListening = true
        logger.info("MediaRemoteBridge started")
    }

    func stop() {
        guard isListening else { return }
        controller.stopListening()
        isListening = false
        lastTrackIdentifier = nil
        lastArtworkID = nil
        currentState = nil
        stateContinuation?.yield(nil)
        stateContinuation?.finish()
        stateContinuation = nil
        logger.info("MediaRemoteBridge stopped")
    }

    // MARK: - Controls

    func togglePlayPause() { controller.togglePlayPause() }
    func nextTrack() { controller.nextTrack() }
    func previousTrack() { controller.previousTrack() }
    func seek(to seconds: Double) { controller.setTime(seconds: seconds) }
}
