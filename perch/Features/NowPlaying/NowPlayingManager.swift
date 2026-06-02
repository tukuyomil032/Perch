// perch/Features/NowPlaying/NowPlayingManager.swift
import Foundation
import Logging

@Observable
@MainActor
final class NowPlayingManager {
    private(set) var currentState: NowPlayingState?

    // nonisolated(unsafe): written once in init on MainActor, read once in deinit — lifecycle guarantees no data race
    private nonisolated(unsafe) var observers: [NSObjectProtocol] = []
    private let logger = Logger(label: "com.tukuyomi032.perch.NowPlayingManager")

    init() {
        MRMediaRemote.shared.registerForNotifications()
        setupNotificationObservers()
        Task { @MainActor [weak self] in await self?.refresh() }
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func refresh() async {
        let info = await MRMediaRemote.shared.fetchNowPlayingInfo()
        let newState = NowPlayingState(from: info)
        if newState != currentState {
            currentState = newState
            logger.debug("Now playing updated: \(newState?.title ?? "nil")")
        }
    }

    func togglePlayPause() {
        MRMediaRemote.shared.sendCommand(.togglePlayPause)
    }

    func nextTrack() {
        MRMediaRemote.shared.sendCommand(.nextTrack)
    }

    func previousTrack() {
        MRMediaRemote.shared.sendCommand(.previousTrack)
    }

    private func setupNotificationObservers() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            .mrNowPlayingInfoDidChange,
            .mrNowPlayingApplicationIsPlayingDidChange,
        ]
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.refresh()
                }
            }
        }
    }
}
