import Foundation
import Logging
import MediaRemoteAdapter

private let logger = Logger(label: "com.tukuyomi032.perch.MediaRemoteBridge")

@Observable
@MainActor
final class MediaRemoteBridge {
    static let shared = MediaRemoteBridge()

    private(set) var isListening = false
    private(set) var currentState: NowPlayingState?

    private nonisolated(unsafe) var stateContinuation: AsyncStream<NowPlayingState?>.Continuation?
    private(set) var stateUpdates: AsyncStream<NowPlayingState?>

    // nonisolated(unsafe): MediaController is not Sendable; callbacks are set from @MainActor,
    // but the controller itself must be accessible without actor isolation.
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
                if let trackInfo,
                    let state = NowPlayingState(fromMediaRemote: trackInfo)
                {
                    self.currentState = state
                    self.stateContinuation?.yield(state)
                } else {
                    self.currentState = nil
                    self.stateContinuation?.yield(nil)
                }
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
        currentState = nil
        stateContinuation?.yield(nil)
        logger.info("MediaRemoteBridge stopped")
    }

    // MARK: - Controls

    func togglePlayPause() { controller.togglePlayPause() }
    func nextTrack() { controller.nextTrack() }
    func previousTrack() { controller.previousTrack() }
    func seek(to seconds: Double) { controller.setTime(seconds: seconds) }
}
