import SwiftUI

/// Two glyphs, right side of `IslandTopBar`: battery, Wi-Fi.
///
/// Deliberately capped at these two (hallmark: don't raise information density). No
/// SSID, no RSSI bars — see `docs/opennook-migration-plan.md` B-3 for why those were
/// left out (Location permission, extra TCC prompts). Bluetooth was dropped entirely:
/// SF Symbols has no official Bluetooth glyph (confirmed by searching the SF Symbols
/// app directly — likely omitted for Bluetooth SIG trademark reasons), and a
/// circled-letter substitute or a private system image were both rejected rather than
/// shipped as a stand-in.
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
        }
        .foregroundStyle(.white.opacity(0.45))
    }
}
