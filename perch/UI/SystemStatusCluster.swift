import SwiftUI

/// Three glyphs, right side of `IslandTopBar`: battery, Wi-Fi, Bluetooth.
///
/// Deliberately capped at these three (hallmark: don't raise information density). No
/// SSID, no RSSI bars, no paired-device names — see `docs/opennook-migration-plan.md`
/// B-3 for why each of those was left out (Location permission, extra TCC prompts).
struct SystemStatusCluster: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let monitor = appState.systemStatusMonitor

        HStack(spacing: 10) {
            if let batterySymbol = SystemStatusIcons.batterySymbolName(
                percentage: monitor.battery.percentage,
                isCharging: monitor.battery.isCharging,
                isPresent: monitor.battery.isPresent
            ) {
                HStack(spacing: 3) {
                    Image(systemName: batterySymbol)
                        .font(.system(size: 11, weight: .medium))
                    if let percentage = monitor.battery.percentage {
                        Text("\(percentage)%")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                }
            }
            Image(systemName: SystemStatusIcons.wifiSymbolName(isPoweredOn: monitor.wifi.isPoweredOn))
                .font(.system(size: 11, weight: .medium))
            Image(
                systemName: SystemStatusIcons.bluetoothSymbolName(
                    isPoweredOn: monitor.bluetooth.isPoweredOn)
            )
            .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.45))
    }
}
