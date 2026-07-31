import AppKit
import EventKit
import ScreenCaptureKit

/// Holds and refreshes the state of every permission Perch's features depend on, for the
/// Settings "Permissions" tab. Each check is preflight-only (no OS prompt) so opening the
/// tab never itself triggers a dialog — `request(_:)` is the only thing that can prompt,
/// and only when the OS is actually able to (see `PermissionStatus.denied`'s doc comment).
@MainActor
@Observable
final class PermissionsStore {
    enum PermissionStatus: Equatable {
        /// Granted.
        case authorized
        /// Never asked yet — `request(_:)` can trigger a real OS prompt.
        case notDetermined
        /// Already answered "no" once. macOS will not show another system prompt for
        /// this identity no matter how many times the app asks — the only way forward
        /// is System Settings, which `request(_:)` opens directly to the right pane.
        case denied
        /// Automation only: the target app isn't running, so `AEDeterminePermissionToAutomateTarget`
        /// can't determine a real status without launching it first.
        case unknown
    }

    enum Kind: String, CaseIterable, Identifiable {
        case calendar
        case screenRecording
        case automationSpotify
        case automationAppleMusic

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .calendar: L10n.string("settings.permissions.calendar")
            case .screenRecording: L10n.string("settings.permissions.screen_recording")
            case .automationSpotify: L10n.string("settings.permissions.automation_spotify")
            case .automationAppleMusic: L10n.string("settings.permissions.automation_apple_music")
            }
        }
    }

    private(set) var statuses: [Kind: PermissionStatus] = [
        .calendar: .notDetermined,
        .screenRecording: .notDetermined,
        .automationSpotify: .notDetermined,
        .automationAppleMusic: .notDetermined,
    ]

    private static let spotifyBundleID = "com.spotify.client"
    private static let appleMusicBundleID = "com.apple.Music"

    /// Preflight-checks every permission without prompting for any of them. Safe to call
    /// whenever the Permissions tab appears — e.g. `.onAppear` — to pick up changes made
    /// in System Settings while Perch was already running.
    func refreshAll() {
        statuses[.calendar] = Self.mapCalendarStatus(EKEventStore.authorizationStatus(for: .event))
        statuses[.screenRecording] = CGPreflightScreenCaptureAccess() ? .authorized : .denied
        statuses[.automationSpotify] = Self.automationStatus(for: Self.spotifyBundleID)
        statuses[.automationAppleMusic] = Self.automationStatus(for: Self.appleMusicBundleID)
    }

    /// Requests the given permission. If it's already `.denied`, no OS prompt is possible
    /// any more — opens the relevant System Settings pane instead. Otherwise triggers the
    /// real permission flow and updates `statuses` with the result.
    func request(_ kind: Kind) async {
        switch kind {
        case .calendar:
            guard statuses[.calendar] != .denied else {
                Self.openSystemSettings(pane: "Privacy_Calendars")
                return
            }
            let granted = (try? await EKEventStore().requestFullAccessToEvents()) ?? false
            statuses[.calendar] = granted ? .authorized : .denied

        case .screenRecording:
            guard statuses[.screenRecording] != .denied else {
                Self.openSystemSettings(pane: "Privacy_ScreenCapture")
                return
            }
            statuses[.screenRecording] = CGRequestScreenCaptureAccess() ? .authorized : .denied

        case .automationSpotify:
            await requestAutomation(bundleID: Self.spotifyBundleID, kind: .automationSpotify)

        case .automationAppleMusic:
            await requestAutomation(bundleID: Self.appleMusicBundleID, kind: .automationAppleMusic)
        }
    }

    private func requestAutomation(bundleID: String, kind: Kind) async {
        guard statuses[kind] != .denied else {
            Self.openSystemSettings(pane: "Privacy_Automation")
            return
        }
        // Off the main actor: AEDeterminePermissionToAutomateTarget with askUserIfNeeded
        // blocks on the system prompt.
        let status = await Task.detached {
            Self.automationStatus(for: bundleID, askUserIfNeeded: true)
        }.value
        statuses[kind] = status
    }

    private static func mapCalendarStatus(_ status: EKAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined: .notDetermined
        case .fullAccess: .authorized
        case .restricted, .denied, .writeOnly: .denied
        @unknown default: .denied
        }
    }

    /// `askUserIfNeeded: false` (the default, used by `refreshAll`) never shows a system
    /// prompt — it only reads the current TCC record. Passing `true` (used by `request(_:)`)
    /// lets the OS show its permission dialog when the status is genuinely undetermined.
    nonisolated private static func automationStatus(
        for bundleID: String, askUserIfNeeded: Bool = false
    ) -> PermissionStatus {
        guard var target = NSAppleEventDescriptor(bundleIdentifier: bundleID).aeDesc?.pointee else {
            return .unknown
        }
        let result = AEDeterminePermissionToAutomateTarget(
            &target, typeWildCard, typeWildCard, askUserIfNeeded)
        switch result {
        case noErr: return .authorized
        case -1743: return .denied  // errAEEventNotPermitted
        case -1744: return .notDetermined  // errAEEventWouldRequireUserConsent
        case -600: return .unknown  // procNotFound — target app isn't running
        default: return .unknown
        }
    }

    private static func openSystemSettings(pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
