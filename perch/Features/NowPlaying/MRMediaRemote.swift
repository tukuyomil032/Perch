// perch/Features/NowPlaying/MRMediaRemote.swift
import Foundation

// MARK: - Command IDs
enum MRCommand: UInt32 {
    case play = 0
    case pause = 1
    case togglePlayPause = 2
    case stop = 3
    case nextTrack = 4
    case previousTrack = 5
}

// MARK: - Notification names
extension Notification.Name {
    static let mrNowPlayingInfoDidChange = Notification.Name(
        "kMRMediaRemoteNowPlayingInfoDidChangeNotification"
    )
    static let mrNowPlayingApplicationIsPlayingDidChange = Notification.Name(
        "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"
    )
}

// MARK: - Info dictionary keys
enum MRInfoKey {
    static let title = "kMRMediaRemoteNowPlayingInfoTitle"
    static let artist = "kMRMediaRemoteNowPlayingInfoArtist"
    static let album = "kMRMediaRemoteNowPlayingInfoAlbum"
    static let artworkData = "kMRMediaRemoteNowPlayingInfoArtworkData"
    static let playbackRate = "kMRMediaRemoteNowPlayingInfoPlaybackRate"
    static let elapsedTime = "kMRMediaRemoteNowPlayingInfoElapsedTime"
    static let duration = "kMRMediaRemoteNowPlayingInfoDuration"
    static let timestamp = "kMRMediaRemoteNowPlayingInfoTimestamp"
}

// MARK: - Dynamic loader (nonisolated, used from MainActor context)
final class MRMediaRemote: @unchecked Sendable {
    static let shared = MRMediaRemote()

    private typealias GetNowPlayingInfoFn =
        @convention(c) (
            DispatchQueue, @escaping (CFDictionary?) -> Void
        ) -> Void
    private typealias SendCommandFn = @convention(c) (UInt32, AnyObject?) -> Bool
    private typealias RegisterFn = @convention(c) (DispatchQueue) -> Void

    private let _getNowPlayingInfo: GetNowPlayingInfoFn?
    private let _sendCommand: SendCommandFn?
    private let _registerForNotifications: RegisterFn?

    private init() {
        let frameworkURL = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, frameworkURL as CFURL) else {
            _getNowPlayingInfo = nil
            _sendCommand = nil
            _registerForNotifications = nil
            return
        }
        func ptr<T>(_ name: String) -> T? {
            guard let raw = CFBundleGetFunctionPointerForName(bundle, name as CFString) else { return nil }
            return unsafeBitCast(raw, to: T.self)
        }
        _getNowPlayingInfo = ptr("MRMediaRemoteGetNowPlayingInfo")
        _sendCommand = ptr("MRMediaRemoteSendCommand")
        _registerForNotifications = ptr("MRMediaRemoteRegisterForNowPlayingNotifications")
    }

    // Async wrapper: resolves on main queue via continuation.
    // Uses nonisolated(unsafe) to ferry the non-Sendable [String:Any]? value
    // across the concurrency boundary from the C callback. The callback always
    // fires on DispatchQueue.main so there is no actual data race.
    nonisolated func fetchNowPlayingInfo() async -> [String: Any]? {
        guard let fn = _getNowPlayingInfo else { return nil }
        nonisolated(unsafe) var result: [String: Any]? = nil
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            fn(.main) { cfDict in
                result = cfDict.map { $0 as NSDictionary as? [String: Any] } ?? nil
                continuation.resume()
            }
        }
        return result
    }

    @discardableResult
    func sendCommand(_ command: MRCommand) -> Bool {
        return _sendCommand?(command.rawValue, nil) ?? false
    }

    @MainActor private var isRegistered = false

    @MainActor func registerForNotifications() {
        guard !isRegistered else { return }
        _registerForNotifications?(.main)
        isRegistered = true
    }
}
