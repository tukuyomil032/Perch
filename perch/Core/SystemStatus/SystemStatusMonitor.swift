import Foundation

/// Bundles the three system status monitors `AppState` exposes to the UI.
///
/// A thin container rather than three separate `AppState` properties, so
/// `SystemStatusCluster` has one thing to read from `appState.systemStatusMonitor`
/// instead of three.
@MainActor
@Observable
final class SystemStatusMonitor {
    let battery = BatteryMonitor()
    let wifi = WiFiMonitor()
    let bluetooth = BluetoothMonitor()
}
