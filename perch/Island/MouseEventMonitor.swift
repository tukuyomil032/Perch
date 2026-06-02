import AppKit
import Defaults

@MainActor
final class MouseEventMonitor {
    private var globalMonitor: Any?
    private weak var appState: AppState?
    private weak var windowController: IslandWindowController?
    private var collapseTask: Task<Void, Never>?

    init(appState: AppState, windowController: IslandWindowController) {
        self.appState = appState
        self.windowController = windowController
    }

    func startMonitoring() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown]
        ) { [weak self] event in
            Task { @MainActor in
                self?.handleEvent(event)
            }
        }
    }

    func stopMonitoring() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
    }

    private func handleEvent(_ event: NSEvent) {
        guard let appState, let window = windowController?.window else { return }
        let mouseLocation = NSEvent.mouseLocation
        let isInWindow = window.frame.contains(mouseLocation)

        switch event.type {
        case .leftMouseDown where !isInWindow && appState.isExpanded:
            scheduleCollapse(after: 0)
        case .mouseMoved where !isInWindow && appState.isExpanded:
            scheduleCollapse(after: Defaults[.autoCollapseDelay])
        case .mouseMoved where isInWindow:
            cancelCollapse()
        default:
            break
        }
    }

    private func scheduleCollapse(after delay: TimeInterval) {
        cancelCollapse()
        collapseTask = Task {
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            appState?.collapse()
        }
    }

    private func cancelCollapse() {
        collapseTask?.cancel()
        collapseTask = nil
    }

}
