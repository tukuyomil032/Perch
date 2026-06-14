import Defaults
import Foundation

enum RefreshInterval: String, CaseIterable, Codable, Defaults.Serializable {
    case oneMinute = "1m"
    case fiveMinutes = "5m"
    case fifteenMinutes = "15m"
    case manual

    nonisolated var timeInterval: TimeInterval? {
        switch self {
        case .oneMinute: return 60
        case .fiveMinutes: return 300
        case .fifteenMinutes: return 900
        case .manual: return nil
        }
    }
}

actor RefreshScheduler {
    private(set) var interval: RefreshInterval
    private(set) var isRunning: Bool = false
    private var task: Task<Void, Never>?
    private var action: (@Sendable () async -> Void)?

    init(interval: RefreshInterval = .fiveMinutes) {
        self.interval = interval
    }

    func start(action: @Sendable @escaping () async -> Void) {
        task?.cancel()
        self.action = action
        guard interval != .manual else { return }
        scheduleLoop()
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    func setInterval(_ newInterval: RefreshInterval) {
        let currentAction = action
        stop()
        interval = newInterval
        if let currentAction {
            start(action: currentAction)
        }
    }

    func triggerNow() {
        guard let action else { return }
        Task {
            await action()
        }
    }

    private func scheduleLoop() {
        let currentInterval = interval
        guard let seconds = currentInterval.timeInterval else { return }
        isRunning = true
        let capturedAction = action
        task = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(seconds))
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                await capturedAction?()
            }
        }
    }
}
