import AppKit
import Foundation
import Logging

@Observable
@MainActor
final class YouTubeMusicAppBridge {
    static let shared = YouTubeMusicAppBridge()

    private(set) var isConnected = false
    private(set) var currentState: NowPlayingState?

    private let logger = Logger(label: "com.tukuyomi032.perch.YTMAppBridge")

    // nonisolated(unsafe): written on MainActor (setup), readable from nonisolated contexts.
    // Same pattern as NowPlayingManager.ncObservers.
    private nonisolated(unsafe) var stateContinuation: AsyncStream<NowPlayingState?>.Continuation?

    let stateUpdates: AsyncStream<NowPlayingState?>

    private let baseURL = URL(string: "http://localhost:26538")!
    private let appBundleID = "com.github.th-ch.youtube-music"
    private let keychainKey = "ytm-app-token"
    private let apiVersion = "v1"

    // nonisolated(unsafe): accessed from deinit / Task cancellation contexts.
    private nonisolated(unsafe) var wsTask: URLSessionWebSocketTask?
    private var token: String?
    private nonisolated(unsafe) var isRefreshingToken = false
    private nonisolated(unsafe) var monitorTask: Task<Void, Never>?
    private nonisolated(unsafe) var terminateTask: Task<Void, Never>?
    private nonisolated(unsafe) var reconnectTask: Task<Void, Never>?

    private init() {
        var cont: AsyncStream<NowPlayingState?>.Continuation?
        stateUpdates = AsyncStream { cont = $0 }
        stateContinuation = cont
    }

    // MARK: - Lifecycle

    func start() {
        monitorTask = Task { [weak self] in
            guard let self else { return }
            if await isAppRunning() { await checkAndConnect() }
            for await notification in NSWorkspace.shared.notificationCenter.notifications(
                named: NSWorkspace.didLaunchApplicationNotification,
                object: NSWorkspace.shared
            ) {
                guard !Task.isCancelled else { return }
                if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                    app.bundleIdentifier == appBundleID
                {
                    await checkAndConnect()
                }
            }
        }
        terminateTask = Task { [weak self] in
            guard let self else { return }
            for await notification in NSWorkspace.shared.notificationCenter.notifications(
                named: NSWorkspace.didTerminateApplicationNotification,
                object: NSWorkspace.shared
            ) {
                guard !Task.isCancelled else { return }
                if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                    app.bundleIdentifier == appBundleID
                {
                    await MainActor.run { self.handleDisconnect() }
                }
            }
        }
    }

    func stop() {
        monitorTask?.cancel()
        terminateTask?.cancel()
        reconnectTask?.cancel()
        handleDisconnect()
    }

    // MARK: - App Detection

    private func isAppRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == appBundleID }
    }

    private func checkAndConnect() async {
        guard isAppRunning() else {
            handleDisconnect()
            return
        }
        do {
            try await authenticate()
            connectWebSocket()
        } catch {
            logger.error("YTM authenticate failed: \(error)")
        }
    }

    // MARK: - Authentication

    private func authenticate() async throws {
        if let cached = KeychainHelper.load(forKey: keychainKey) {
            token = cached
            logger.debug("YTM: using cached token")
            return
        }
        var req = URLRequest(url: baseURL.appending(path: "auth/perch"))
        req.httpMethod = "POST"
        req.timeoutInterval = 5
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw BridgeError.invalidResponse }
        if http.statusCode == 403 {
            logger.warning("YTM: user denied auth request in YTM app")
            throw BridgeError.authDenied
        }
        guard http.statusCode == 200 else { throw BridgeError.authFailed(http.statusCode) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let accessToken = json["accessToken"] as? String
        else {
            throw BridgeError.invalidResponse
        }
        token = accessToken
        try KeychainHelper.save(accessToken, forKey: keychainKey)
        logger.info("YTM: authenticated and token cached")
    }

    // MARK: - WebSocket

    private func connectWebSocket() {
        wsTask?.cancel(with: .normalClosure, reason: nil)
        var req = URLRequest(url: baseURL.appending(path: "api/\(apiVersion)/ws"))
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        wsTask = URLSession.shared.webSocketTask(with: req)
        wsTask?.resume()
        isConnected = true
        logger.info("YTM: WebSocket connected")
        receiveLoop()
    }

    private func handleDisconnect() {
        wsTask?.cancel(with: .normalClosure, reason: nil)
        wsTask = nil
        isConnected = false
        currentState = nil
        stateContinuation?.yield(nil)
    }

    private func receiveLoop() {
        wsTask?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .success(let msg):
                    if case .string(let text) = msg { self.handleMessage(text) }
                    self.receiveLoop()
                case .failure(let err):
                    logger.warning("YTM WS error: \(err.localizedDescription)")
                    self.isConnected = false
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let event = json["event"] as? String
        else { return }

        logger.debug("YTM event: \(event)")

        switch event {
        case "PLAYER_INFO", "VIDEO_CHANGED", "PLAYER_STATE_CHANGED", "POSITION_CHANGED":
            let payload = json["data"] as? [String: Any] ?? json
            if let state = NowPlayingState(fromYTMAppEvent: payload) {
                currentState = state
                stateContinuation?.yield(state)
            }
        default:
            break
        }
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, !Task.isCancelled, isAppRunning() else { return }
            logger.info("YTM: reconnecting...")
            connectWebSocket()
        }
    }

    // MARK: - Playback Controls

    func togglePlayPause() async { await send("toggle-play") }
    func nextTrack() async { await send("next") }
    func previousTrack() async { await send("previous") }
    func seek(to seconds: Double) async { await send("seek-to", body: ["seconds": seconds]) }

    private func send(_ command: String, body: [String: Any]? = nil) async {
        guard let token else { return }
        var req = URLRequest(url: baseURL.appending(path: "api/\(apiVersion)/\(command)"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 3
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                guard !isRefreshingToken else { return }
                isRefreshingToken = true
                defer { isRefreshingToken = false }
                KeychainHelper.delete(forKey: keychainKey)
                self.token = nil
                try? await authenticate()
            }
        } catch {
            logger.error("YTM command \(command) failed: \(error)")
        }
    }

    enum BridgeError: Error {
        case authDenied
        case authFailed(Int)
        case invalidResponse
    }
}
