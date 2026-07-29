import Foundation
import Testing

@testable import perch

@Suite("SystemStatusIcons")
struct SystemStatusIconMappingTests {
    @Test("battery symbol is nil when not present")
    func batteryAbsent() {
        #expect(
            SystemStatusIcons.batterySymbolName(percentage: 80, isCharging: false, isPresent: false)
                == nil)
    }

    @Test("battery symbol is nil when present but percentage is unknown")
    func batteryUnknownPercentage() {
        #expect(
            SystemStatusIcons.batterySymbolName(percentage: nil, isCharging: false, isPresent: true)
                == nil)
    }

    @Test("charging always wins over percentage tier")
    func chargingTakesPriority() {
        #expect(
            SystemStatusIcons.batterySymbolName(percentage: 5, isCharging: true, isPresent: true)
                == "battery.100percent.bolt")
    }

    @Test("percentage tiers map to the expected glyph")
    func percentageTiers() {
        let cases: [(Int, String)] = [
            (0, "battery.0percent"),
            (9, "battery.0percent"),
            (10, "battery.25percent"),
            (34, "battery.25percent"),
            (35, "battery.50percent"),
            (59, "battery.50percent"),
            (60, "battery.75percent"),
            (89, "battery.75percent"),
            (90, "battery.100percent"),
            (100, "battery.100percent"),
        ]
        for (percentage, expected) in cases {
            #expect(
                SystemStatusIcons.batterySymbolName(
                    percentage: percentage, isCharging: false, isPresent: true) == expected)
        }
    }

    @Test("wifi symbol reflects power state")
    func wifiSymbol() {
        #expect(SystemStatusIcons.wifiSymbolName(isPoweredOn: true) == "wifi")
        #expect(SystemStatusIcons.wifiSymbolName(isPoweredOn: false) == "wifi.slash")
    }
}
