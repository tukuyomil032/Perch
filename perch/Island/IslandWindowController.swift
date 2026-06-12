import AppKit
import Defaults
import Logging
import SwiftUI

private let logger = Logger(label: "com.tukuyomi032.perch.IslandWindowController")

@MainActor
final class IslandWindowController: NSWindowController {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        let (environment, screen) = Self.resolveScreenEnvironment()
        let notchSize = environment.notchSize
        let mode: IslandMode = notchSize == .zero ? .floatingPill : .physicalNotch(notchSize: notchSize)
        appState.isPhysicalNotch = (mode != .floatingPill)
        let frame = IslandGeometry.compactFrame(mode: mode, environment: environment)

        logger.info(
            "initializing island window",
            metadata: [
                "screen": .string(screen.localizedName),
                "simulationMode": .string(Defaults[.notchSimulationMode].rawValue),
                "mode": .string("\(mode)"),
                "frame": .string("\(frame)"),
            ])
        NSScreen.logScreenDiagnostics()

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

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func updateLayout() {
        let (environment, _) = Self.resolveScreenEnvironment()
        let notchSize = environment.notchSize
        let mode: IslandMode = notchSize == .zero ? .floatingPill : .physicalNotch(notchSize: notchSize)
        appState.isPhysicalNotch = (mode != .floatingPill)
        let frame =
            appState.isExpanded
            ? IslandGeometry.expandedFrame(
                mode: mode, environment: environment,
                height: mode == .floatingPill ? appState.expandedWindowHeight : nil)
            : IslandGeometry.compactFrame(
                mode: mode, environment: environment,
                width: mode == .floatingPill ? appState.compactWindowWidth : nil)
        window?.setFrame(frame, display: true)

        logger.debug(
            "updateLayout",
            metadata: [
                "mode": .string("\(mode)"),
                "windowFrame": .string("\(window?.frame ?? .zero)"),
                "contentViewFrame": .string("\(window?.contentView?.frame ?? .zero)"),
                "screenMidX": .stringConvertible(environment.frame.midX),
                "pillMidX": .stringConvertible(frame.midX),
            ])
    }

    private static func resolveScreenEnvironment() -> (ScreenEnvironment, NSScreen) {
        let screen = NSScreen.perchPreferredScreen ?? NSScreen.main!
        switch Defaults[.notchSimulationMode] {
        case .auto:
            return (ScreenEnvironment.live(screen: screen), screen)
        case .forceNotched:
            return (ScreenEnvironment.mockNotchedMacBook(frame: screen.frame), screen)
        case .forceNonNotched:
            return (ScreenEnvironment.mockNonNotchedMac(frame: screen.frame), screen)
        }
    }

    private func startObserving() {
        observeExpanded()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        logger.info("screen parameters changed — recalculating layout")
        NSScreen.logScreenDiagnostics()
        updateLayout()
    }

    private func observeExpanded() {
        withObservationTracking {
            _ = appState.isExpanded
            _ = appState.expandedWindowHeight
            _ = appState.compactWindowWidth
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateLayout()
                self?.observeExpanded()
            }
        }
    }
}
