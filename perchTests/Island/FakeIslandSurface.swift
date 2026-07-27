import AppKit
import Combine

@testable import perch

/// In-memory stand-in for the vendored notch surface.
///
/// Exists so `NookBridge` — and, from A5 on, `AppState`'s transition tests — can be
/// driven without mounting a real `NSPanel`, and so tests can play back hover and
/// lifecycle events in an order a real surface would only produce with a live cursor.
@MainActor
final class FakeIslandSurface: IslandSurfaceDriving {
    private let hoverSubject = CurrentValueSubject<Bool, Never>(false)

    var isHovering: Bool { hoverSubject.value }
    var isHoveringPublisher: AnyPublisher<Bool, Never> { hoverSubject.eraseToAnyPublisher() }

    var staysExpandedOnHoverExit = false
    var onExpand: (@MainActor () -> Void)?
    var onCompact: (@MainActor () -> Void)?

    private(set) var expandCallCount = 0
    private(set) var compactCallCount = 0
    private(set) var configureWindowCallCount = 0

    /// `false` reproduces a hidden surface, where there is no window to configure.
    var hasLiveWindow = true

    /// The window `configureWindow` hands out, so a test can assert on what was applied.
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 100, height: 40),
        styleMask: [.borderless],
        backing: .buffered,
        defer: true
    )

    func expand(on screen: NSScreen?) async {
        expandCallCount += 1
        onExpand?()
    }

    func compact(on screen: NSScreen?) async {
        compactCallCount += 1
        onCompact?()
    }

    @discardableResult
    func configureWindow(_ apply: (NSWindow) -> Void) -> Bool {
        guard hasLiveWindow else { return false }
        configureWindowCallCount += 1
        apply(window)
        return true
    }

    // MARK: - Test drivers

    /// Plays back a hover transition the way the real surface publishes it.
    func setHovering(_ hovering: Bool) {
        hoverSubject.send(hovering)
    }
}
