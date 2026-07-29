import CoreWLAN
import Foundation

/// Watches Wi-Fi power state only — no SSID, no RSSI.
///
/// `CWInterface.ssid()` requires Location Services authorization on macOS 14+; Perch
/// deliberately never asks for that permission, so this monitor never reads it. See
/// `docs/opennook-migration-plan.md` B-3 for the "zero permission dialogs" decision.
///
/// Polled on a coarse timer rather than `CWEventDelegate`: that delegate API is built
/// around a run-loop client Perch would otherwise have no reason to keep alive, for a
/// menu-bar glyph that only needs to be roughly current.
@MainActor
@Observable
final class WiFiMonitor {
    private(set) var isPoweredOn = false

    // `nonisolated(unsafe)`: written once on the main actor in `init` and read only from
    // the nonisolated `deinit` — no concurrent access is possible.
    nonisolated(unsafe) private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit {
        timer?.invalidate()
    }

    private func refresh() {
        isPoweredOn = CWWiFiClient.shared().interface()?.powerOn() ?? false
    }
}
