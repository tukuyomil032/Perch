import Foundation
import IOBluetooth

/// Watches Bluetooth power state only — ON/OFF, no paired-device names.
///
/// Uses `IOBluetooth`, not `CoreBluetooth`: the latter would require
/// `NSBluetoothAlwaysUsageDescription` and a permission dialog neither Perch nor the
/// user wants for a menu-bar glyph. See `docs/opennook-migration-plan.md` B-3.
@MainActor
@Observable
final class BluetoothMonitor {
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
        isPoweredOn = IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON
    }
}
