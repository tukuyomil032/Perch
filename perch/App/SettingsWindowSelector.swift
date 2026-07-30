import Foundation

/// Picks the Settings window out of `NSApp.windows` without depending on `NSWindow` directly,
/// so the selection logic can be unit tested without a real window server.
nonisolated enum SettingsWindowSelector {
    struct Candidate {
        let canBecomeKey: Bool
        let isVisible: Bool
        /// True for chrome windows that are always keyable+visible (e.g. `NookPanel`) and
        /// must never be mistaken for the Settings window.
        let isChrome: Bool
    }

    /// Returns the index of the first candidate that is keyable, visible, and not chrome.
    nonisolated static func selectTarget(from candidates: [Candidate]) -> Int? {
        candidates.firstIndex { $0.canBecomeKey && $0.isVisible && !$0.isChrome }
    }
}
