import Testing

@testable import perch

@Suite("IslandChromeStyle")
struct IslandChromeStyleTests {
    @Test("notch maps to NookPresentation.notch")
    func notchMapsToNookNotch() {
        #expect(IslandChromeStyle.notch.nookPresentation == .notch)
    }

    @Test("floating maps to NookPresentation.floating")
    func floatingMapsToNookFloating() {
        #expect(IslandChromeStyle.floating.nookPresentation == .floating)
    }

    @Test("legacy .auto migrates to .notch")
    func legacyAutoMigratesToNotch() {
        #expect(IslandChromeStyle.migrating(fromLegacy: NotchSimulationMode.auto.rawValue) == .notch)
    }

    @Test("legacy .forceNotched migrates to .notch")
    func legacyForceNotchedMigratesToNotch() {
        #expect(IslandChromeStyle.migrating(fromLegacy: NotchSimulationMode.forceNotched.rawValue) == .notch)
    }

    @Test("legacy .forceNonNotched migrates to .floating")
    func legacyForceNonNotchedMigratesToFloating() {
        #expect(IslandChromeStyle.migrating(fromLegacy: NotchSimulationMode.forceNonNotched.rawValue) == .floating)
    }

    @Test("unrecognized legacy raw value falls back to .notch")
    func unrecognizedRawValueFallsBackToNotch() {
        #expect(IslandChromeStyle.migrating(fromLegacy: "someUnknownLegacyValue") == .notch)
    }

    @Test("nil legacy raw value (no prior preference) falls back to .notch")
    func nilRawValueFallsBackToNotch() {
        #expect(IslandChromeStyle.migrating(fromLegacy: nil) == .notch)
    }
}
