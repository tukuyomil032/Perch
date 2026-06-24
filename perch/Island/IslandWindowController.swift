import AppKit
import Defaults
import Logging
import SwiftUI

private let logger = Logger(label: "com.tukuyomi032.perch.IslandWindowController")

@MainActor
final class IslandWindowController: NSWindowController {
    private let appState: AppState
    private var pendingLayoutTask: Task<Void, Never>?
    // nonisolated(unsafe): written once on @MainActor (startObserving) and
    // read only in deinit (nonisolated). No concurrent access occurs.
    nonisolated(unsafe) private var notchModeObservation: (any Defaults.Observation)?
    private var lastExpandedTarget: Bool?

    private var islandWindow: IslandWindow? { window as? IslandWindow }

    init(appState: AppState) {
        self.appState = appState
        let (environment, screen) = Self.resolveScreenEnvironment()
        let notchSize = environment.notchSize
        let mode: IslandMode = notchSize == .zero ? .floatingPill : .physicalNotch(notchSize: notchSize)
        appState.isPhysicalNotch = (mode != .floatingPill)
        let frame = IslandGeometry.compactFrame(mode: mode, environment: environment)
        appState.compactWindowSize = frame.size

        logger.info(
            "initializing island window",
            metadata: [
                "screen": .string(screen.localizedName),
                "simulationMode": .string(Defaults[.notchSimulationMode].rawValue),
                "mode": .string("\(mode)"),
                "frame": .string("\(frame)"),
            ])
        #if DEBUG
        NSScreen.logScreenDiagnostics()
        #endif

        let window = IslandWindow(contentRect: frame, styleMask: [], backing: .buffered, defer: false)

        // Use a fixed AppKit container view with NSHostingView pinned inside.
        // This severs SwiftUI's window-size negotiation path: the AppKit container
        // owns the frame, and NSHostingView renders into whatever space it is given.
        let containerView = NSView(frame: NSRect(origin: .zero, size: frame.size))
        containerView.translatesAutoresizingMaskIntoConstraints = true
        containerView.autoresizingMask = [.width, .height]
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor
        containerView.layer?.masksToBounds = true
        containerView.layer?.cornerRadius = DesignSystem.pillCornerRadius
        containerView.layer?.maskedCorners = [
            .layerMinXMinYCorner, .layerMaxXMinYCorner,
            .layerMinXMaxYCorner, .layerMaxXMaxYCorner,
        ]

        let hostingView = NSHostingView(rootView: RootIslandView().environment(appState))
        hostingView.sizingOptions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false

        containerView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        window.contentView = containerView

        super.init(window: window)
        window.applyManagedFrame(frame, display: true)
        window.orderFrontRegardless()
        lastExpandedTarget = appState.isExpanded  // false at launch; ensures first expand gets .open transition
        startObserving()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        pendingLayoutTask?.cancel()
        notchModeObservation?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    func updateLayout() {
        let (environment, _) = Self.resolveScreenEnvironment()
        let notchSize = environment.notchSize
        let mode: IslandMode =
            notchSize == .zero
            ? .floatingPill
            : .physicalNotch(notchSize: notchSize)

        appState.isPhysicalNotch = (mode != .floatingPill)

        let expands = appState.isExpanded

        let compactFrame = IslandGeometry.compactFrame(
            mode: mode,
            environment: environment,
            width: mode == .floatingPill ? appState.compactWindowWidth : nil,
            height: mode == .floatingPill ? appState.compactWindowHeight : nil
        )
        appState.compactWindowSize = compactFrame.size

        let frame: CGRect =
            expands
            ? IslandGeometry.expandedFrame(
                mode: mode,
                environment: environment,
                height: appState.expandedWindowHeight
            )
            : compactFrame

        let transition: IslandWindowFrameTransition?
        if let lastExpandedTarget, lastExpandedTarget != expands {
            transition = expands ? .open : .close
        } else {
            transition = nil
        }

        // Race guard: if a frame animation is currently in flight AND we need to apply a
        // direction-change transition (open→close or close→open), the NSAnimationContext
        // layers can conflict and leave the window at a wrong intermediate frame.
        // Defer the update until the current animation completes (~500ms covers the close
        // duration of 460ms with a small buffer). When the deferred task fires it re-calls
        // updateLayout(), which re-reads appState and applies the correct frame.
        if let win = islandWindow, win.isAnimatingFrame, transition != nil {
            pendingLayoutTask?.cancel()
            pendingLayoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(
                    for: .milliseconds(
                        Int(DesignSystem.Motion.closeDuration * 1000) + 40
                    ))
                guard !Task.isCancelled else { return }
                self?.updateLayout()
            }
            return
        }

        lastExpandedTarget = expands

        // Sync CALayer cornerRadius on the contentView so the NSWindow backing
        // (glass effect / VibrancyBackground) is clipped to the correct shape.
        // SwiftUI .clipShape() only clips within SwiftUI's render tree; the
        // NSView contentView layer remains rectangular without this.
        if let layer = window?.contentView?.layer {
            let cornerRadius: CGFloat =
                expands
                ? DesignSystem.cardCornerRadius
                : DesignSystem.pillCornerRadius
            layer.cornerRadius = cornerRadius
            layer.maskedCorners = [
                .layerMinXMinYCorner, .layerMaxXMinYCorner,
                .layerMinXMaxYCorner, .layerMaxXMaxYCorner,
            ]
        }

        islandWindow?.applyManagedFrame(frame, display: true, transition: transition)

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
        notchModeObservation = Defaults.observe(.notchSimulationMode) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleLayoutUpdate()
            }
        }
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        logger.info("screen parameters changed — recalculating layout")
        #if DEBUG
        NSScreen.logScreenDiagnostics()
        #endif
        scheduleLayoutUpdate()
    }

    private func scheduleLayoutUpdate() {
        pendingLayoutTask?.cancel()
        pendingLayoutTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            self?.updateLayout()
        }
    }

    private func observeExpanded() {
        withObservationTracking {
            _ = appState.isExpanded
            _ = appState.presetStore.activePresetID
            if appState.isExpanded {
                // When expanded, only track height — avoids pulling in aiUsageStore.activeUsage
                // which fires on every refresh() chunk and storms applyManagedFrame() calls
                _ = appState.expandedWindowHeight
            } else {
                _ = appState.compactWindowWidth
                _ = appState.compactWindowHeight
            }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleLayoutUpdate()
                self?.observeExpanded()
            }
        }
    }
}
