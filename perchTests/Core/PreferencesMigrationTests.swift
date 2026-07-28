import Defaults
import Foundation
import Testing

@testable import perch

/// Runs against `UserDefaults.standard` — the store the migration actually faces in
/// production — with every key it touches snapshotted and restored around each test, so a
/// run leaves the developer's own Perch preferences exactly as it found them.
///
/// A throwaway `UserDefaults(suiteName:)` looks like the tidier choice and is a trap: a
/// suite instance's search list still includes the application domain, so reads fall
/// through to whatever is in `standard`. Worse for this particular type, declaring a
/// `Defaults.Key` calls `suite.register(defaults:)` with the key's default value, which
/// lands in the registration domain — so `object(forKey:)` returns non-nil for
/// `islandChromeStyle` on a completely fresh install. Tests written against a suite would
/// therefore pass or fail based on the machine they ran on, and could not distinguish
/// "the user set this" from "the key was declared."
///
/// `.serialized` because the tests share one store. Note that swift-testing runs *suites*
/// in parallel: `rawStringRoundTripsThroughDefaults` writes `Defaults[.islandChromeStyle]`,
/// so no other suite may read or write that key concurrently. Nothing else does today —
/// if that changes, these tests need a shared lock rather than suite-local serialization.
@Suite("PreferencesMigration", .serialized)
@MainActor
struct PreferencesMigrationTests {
    private static let chromeKey = Defaults.Keys.islandChromeStyle.name
    private static let legacyChromeKey = PreferencesMigration.LegacyKey.notchSimulationMode
    private static let touchedKeys = [
        chromeKey,
        legacyChromeKey,
        PreferencesMigration.LegacyKey.pillSize,
        PreferencesMigration.LegacyKey.pillBackgroundStyle,
    ]

    /// Snapshots every key the migration touches, hands the caller a clean slate, and
    /// restores the snapshot afterwards whatever the body does.
    private func withCleanStore(_ body: (UserDefaults) -> Void) {
        let store = UserDefaults.standard
        let snapshot = Self.touchedKeys.map { ($0, store.object(forKey: $0)) }
        for key in Self.touchedKeys { store.removeObject(forKey: key) }
        defer {
            for (key, value) in snapshot {
                if let value {
                    store.set(value, forKey: key)
                } else {
                    store.removeObject(forKey: key)
                }
            }
        }
        body(store)
    }

    @Test("a legacy forceNonNotched preference becomes .floating")
    func migratesLegacyFloating() {
        withCleanStore { store in
            store.set("forceNonNotched", forKey: Self.legacyChromeKey)
            PreferencesMigration.migrateIslandChromeStyle(in: store)
            #expect(store.string(forKey: Self.chromeKey) == IslandChromeStyle.floating.rawValue)
        }
    }

    @Test("a legacy auto preference becomes .notch")
    func migratesLegacyAuto() {
        withCleanStore { store in
            store.set("auto", forKey: Self.legacyChromeKey)
            PreferencesMigration.migrateIslandChromeStyle(in: store)
            #expect(store.string(forKey: Self.chromeKey) == IslandChromeStyle.notch.rawValue)
        }
    }

    @Test("a fresh install is left entirely alone")
    func freshInstallIsUntouched() {
        withCleanStore { store in
            // Pre-set a value the migration must not touch. Asserting "nothing was
            // written" directly is impossible: declaring a `Defaults.Key` registers its
            // default, so `object(forKey:)` is never nil for the new key.
            store.set(IslandChromeStyle.floating.rawValue, forKey: Self.chromeKey)
            PreferencesMigration.migrateIslandChromeStyle(in: store)
            #expect(store.string(forKey: Self.chromeKey) == IslandChromeStyle.floating.rawValue)
        }
    }

    @Test("consuming the legacy key makes the migration one-shot")
    func consumesLegacyKey() {
        withCleanStore { store in
            store.set("forceNonNotched", forKey: Self.legacyChromeKey)
            PreferencesMigration.migrateIslandChromeStyle(in: store)
            #expect(store.object(forKey: Self.legacyChromeKey) == nil)
        }
    }

    @Test("re-running the migration does not revert a later user choice")
    func isIdempotent() {
        withCleanStore { store in
            store.set("forceNonNotched", forKey: Self.legacyChromeKey)
            PreferencesMigration.migrateIslandChromeStyle(in: store)
            // User then picks the other style in Settings.
            store.set(IslandChromeStyle.notch.rawValue, forKey: Self.chromeKey)
            PreferencesMigration.migrateIslandChromeStyle(in: store)
            #expect(store.string(forKey: Self.chromeKey) == IslandChromeStyle.notch.rawValue)
        }
    }

    @Test("retired pill keys are removed")
    func removesRetiredPillKeys() {
        withCleanStore { store in
            store.set("large", forKey: PreferencesMigration.LegacyKey.pillSize)
            store.set("glassWhite", forKey: PreferencesMigration.LegacyKey.pillBackgroundStyle)
            PreferencesMigration.removeRetiredKeys(in: store)
            #expect(store.object(forKey: PreferencesMigration.LegacyKey.pillSize) == nil)
            #expect(store.object(forKey: PreferencesMigration.LegacyKey.pillBackgroundStyle) == nil)
        }
    }

    @Test("removeRetiredKeys never touches the legacy chrome key")
    func removeRetiredKeysLeavesChromeKeyToTheMigration() {
        withCleanStore { store in
            store.set("forceNonNotched", forKey: Self.legacyChromeKey)
            // It carries information, so only `migrateIslandChromeStyle` may consume it —
            // and only after the replacement has been written.
            PreferencesMigration.removeRetiredKeys(in: store)
            #expect(store.string(forKey: Self.legacyChromeKey) == "forceNonNotched")
        }
    }

    @Test("runAll migrates and cleans up in one pass")
    func runAllMigratesThenCleansUp() {
        withCleanStore { store in
            store.set("forceNonNotched", forKey: Self.legacyChromeKey)
            store.set("large", forKey: PreferencesMigration.LegacyKey.pillSize)
            PreferencesMigration.runAll(in: store)
            #expect(store.string(forKey: Self.chromeKey) == IslandChromeStyle.floating.rawValue)
            #expect(store.object(forKey: Self.legacyChromeKey) == nil)
            #expect(store.object(forKey: PreferencesMigration.LegacyKey.pillSize) == nil)
        }
    }

    /// Pins the assumption the migration's raw-value write depends on: `Defaults` persists
    /// a `String`-backed `RawRepresentable` as the bare raw string. If a `Defaults` upgrade
    /// ever wrapped it (JSON, a plist dict), the migration would still write a plain string
    /// and every migrated user would silently fall back to the default — this fails first.
    @Test("a raw string written directly round-trips through Defaults")
    func rawStringRoundTripsThroughDefaults() {
        withCleanStore { store in
            store.set(IslandChromeStyle.floating.rawValue, forKey: Self.chromeKey)
            #expect(Defaults[.islandChromeStyle] == .floating)

            // ...and the reverse: what Defaults writes is readable as a bare string.
            Defaults[.islandChromeStyle] = .notch
            #expect(store.string(forKey: Self.chromeKey) == IslandChromeStyle.notch.rawValue)
        }
    }
}
