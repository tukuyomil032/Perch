import Foundation
import Logging
import MediaRemoteAdapter

private let logger = Logger(label: "com.tukuyomi032.perch.MediaRemoteBridge")

@Observable
@MainActor
final class MediaRemoteBridge {
    static let shared = MediaRemoteBridge()

    private(set) var isListening = false
    /// Set by NowPlayingManager to restrict events to specific apps (e.g. Chromium browsers).
    /// Return true to accept the event, false to ignore it. Nil means accept all.
    var bundleIdentifierFilter: ((String?) -> Bool)? = nil
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
            MainActor.assumeIsolated { [weak self] in
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
                // Reject events not from an allowed application (e.g. non-Chromium apps)
                if let filter = self.bundleIdentifierFilter,
                    !filter(trackInfo.payload.bundleIdentifier)
                {
                    return
                }

                let payload = trackInfo.payload
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
                        fallbackElapsedTime: fallbackElapsed
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
            MainActor.assumeIsolated { [weak self] in
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
