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

    // The three legacy raw values are spelled as string literals because
    // `NotchSimulationMode` no longer exists — A5 deleted it. That is exactly what makes
    // these assertions worth keeping: they now pin the *on-disk* strings shipped builds
    // wrote into `UserDefaults`, which no amount of Swift-side refactoring can change.

    @Test("legacy .auto migrates to .notch")
    func legacyAutoMigratesToNotch() {
        #expect(IslandChromeStyle.migrating(fromLegacy: "auto") == .notch)
    }

    @Test("legacy .forceNotched migrates to .notch")
    func legacyForceNotchedMigratesToNotch() {
        #expect(IslandChromeStyle.migrating(fromLegacy: "forceNotched") == .notch)
    }

    @Test("legacy .forceNonNotched migrates to .floating")
    func legacyForceNonNotchedMigratesToFloating() {
        #expect(IslandChromeStyle.migrating(fromLegacy: "forceNonNotched") == .floating)
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
