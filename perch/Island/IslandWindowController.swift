import AppKit
import SwiftUI

@MainActor
final class IslandWindowController: NSWindowController {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        let screen = NSScreen.perchPreferredScreen ?? NSScreen.main!
        let notchSize = screen.perchNotchSize
        let mode: IslandMode = notchSize == .zero ? .floatingPill : .physicalNotch(notchSize: notchSize)
        let frame = IslandGeometry.compactFrame(mode: mode, screen: screen)

        let window = IslandWindow(contentRect: frame, styleMask: [], backing: .buffered, defer: false)
        let rootView = RootIslandView().environment(appState)
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = .clear
        window.contentViewController = hostingController

        super.init(window: window)
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
        startObserving()
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateLayout() {
        guard let screen = NSScreen.perchPreferredScreen ?? NSScreen.main else { return }
        let notchSize = screen.perchNotchSize
        let mode: IslandMode = notchSize == .zero ? .floatingPill : .physicalNotch(notchSize: notchSize)
        let frame =
            appState.isExpanded
            ? IslandGeometry.expandedFrame(mode: mode, screen: screen)
            : IslandGeometry.compactFrame(mode: mode, screen: screen)
        // Synchronized with SwiftUI spring(response:0.30, dampingFraction:0.88)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.30
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            window?.animator().setFrame(frame, display: true)
        }
    }

    private func startObserving() {
        observeExpanded()
    }

    private func observeExpanded() {
        withObservationTracking {
            _ = appState.isExpanded
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateLayout()
                self?.observeExpanded()
            }
        }
    }
}
