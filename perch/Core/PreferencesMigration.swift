import Defaults
import Foundation

/// One-shot migrations of persisted preferences whose *shape* changed between releases.
///
/// `Defaults` has no migration hook of its own — a `Key` only ever supplies a default for
/// a value that is absent, which cannot express "this key was replaced by that one." So
/// the handful of renames Perch has actually shipped live here, run once from
/// `applicationDidFinishLaunching` before anything reads the new keys.
///
/// Every migration below is written to be **idempotent and re-runnable**: it decides
/// whether to act by looking at the store, never by a "have I run yet?" flag. A version
/// counter would be one more thing to get wrong, and would silently skip a user who
/// downgraded and upgraded again.
enum PreferencesMigration {
    /// Raw `UserDefaults` key names, not `Defaults.Key`s. These name preferences that no
    /// longer exist in the codebase — there is deliberately nothing left to reference.
    enum LegacyKey {
        /// `NotchSimulationMode` (`auto` / `forceNotched` / `forceNonNotched`), replaced by
        /// the two-valued `islandChromeStyle`.
        static let notchSimulationMode = "notchSimulationMode"
        /// `PillSizePreset` (S/M/L). Removed outright: the vendored surface sizes the
        /// compact chrome from the notch height and its content, so there is no pill
        /// dimension left for a user to choose.
        static let pillSize = "pillSize"
        /// `PillBackgroundStyle` (glassBlack / glassWhite). Removed outright: it only ever
        /// tinted the capsule `CompactPillView` drew, and the backdrop is now the vendored
        /// surface's, chosen by `NookBridge.makeBackdrop(reduceTransparency:)`.
        static let pillBackgroundStyle = "pillBackgroundStyle"
    }

    /// Runs every pending migration. Call once, early, before any `Defaults[...]` read that
    /// a migration is meant to populate.
    static func runAll(in store: UserDefaults = .standard) {
        migrateIslandChromeStyle(in: store)
        removeRetiredKeys(in: store)
    }

    /// Carries a persisted `notchSimulationMode` over to `islandChromeStyle`, then drops
    /// the legacy key.
    ///
    /// **Gated on the presence of the legacy key, deliberately.** The obvious gate — "only
    /// write `islandChromeStyle` if it isn't set yet" — cannot be implemented: declaring a
    /// `Defaults.Key` calls `suite.register(defaults:)` with the key's default value, so
    /// `object(forKey: "islandChromeStyle")` returns that registered default and is *never*
    /// `nil`. A guard written that way would never fire and nobody would ever be migrated.
    /// `UserDefaults` exposes no per-domain presence check short of
    /// `persistentDomain(forName:)`, which would drag a bundle-identifier lookup into this
    /// type for no gain.
    ///
    /// Keying off the legacy value avoids the problem entirely and is self-limiting:
    /// consuming the key is what makes the migration one-shot. Re-running it is a no-op,
    /// and a user who later picks a style in Settings can't have it reverted, because
    /// there is no longer a legacy value to migrate from. This is safe precisely because
    /// `islandChromeStyle` is new in this release — no shipped build ever wrote it, so
    /// "legacy key present" implies "new key never chosen by the user."
    ///
    /// Writes the raw value straight into `store` rather than through
    /// `Defaults[.islandChromeStyle]`, so that reads and writes both go through the
    /// injected store. Assigning through `Defaults` would always target the *standard*
    /// suite regardless of what was injected, which would make the seam a lie and the
    /// tests meaningless. `IslandChromeStyle` is a `String`-backed `RawRepresentable`,
    /// which `Defaults` persists as exactly that bare raw string —
    /// `PreferencesMigrationTests.rawStringRoundTripsThroughDefaults` pins that contract so
    /// a `Defaults` upgrade that changed the encoding could not slip through.
    static func migrateIslandChromeStyle(in store: UserDefaults = .standard) {
        guard let legacy = store.string(forKey: LegacyKey.notchSimulationMode) else { return }

        let migrated = IslandChromeStyle.migrating(fromLegacy: legacy)
        store.set(migrated.rawValue, forKey: Defaults.Keys.islandChromeStyle.name)
        store.removeObject(forKey: LegacyKey.notchSimulationMode)
    }

    /// Deletes preferences that were removed outright rather than renamed, so they stop
    /// occupying the user's defaults domain (and stop reappearing in exported plists as
    /// phantom settings).
    ///
    /// `notchSimulationMode` is *not* handled here — it carries information, so
    /// ``migrateIslandChromeStyle(in:)`` consumes it only after successfully writing the
    /// replacement. The keys below carry none, so they can go unconditionally. Safe to
    /// re-run: `removeObject(forKey:)` on an absent key is a no-op.
    static func removeRetiredKeys(in store: UserDefaults = .standard) {
        store.removeObject(forKey: LegacyKey.pillSize)
        store.removeObject(forKey: LegacyKey.pillBackgroundStyle)
    }
}
