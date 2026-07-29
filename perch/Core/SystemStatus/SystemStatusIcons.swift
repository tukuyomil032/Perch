import Foundation

/// Pure "value → SF Symbol name" mappings for the system status cluster.
///
/// Split out from the monitors so the icon selection can be unit-tested without any
/// hardware access (IOKit / CoreWLAN / IOBluetooth), matching the pattern
/// `WidgetSizeMetrics` already uses for its own pure lookup table.
nonisolated enum SystemStatusIcons {
    static func batterySymbolName(percentage: Int?, isCharging: Bool, isPresent: Bool) -> String? {
        guard isPresent, let percentage else { return nil }
        if isCharging { return "battery.100percent.bolt" }
        switch percentage {
        case ..<10: return "battery.0percent"
        case ..<35: return "battery.25percent"
        case ..<60: return "battery.50percent"
        case ..<90: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    static func wifiSymbolName(isPoweredOn: Bool) -> String {
        isPoweredOn ? "wifi" : "wifi.slash"
    }
}
