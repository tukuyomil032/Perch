import Defaults
import Foundation

/// How the Perch island chrome presents itself: notch-attached (the default, "Atoll
/// 風" pseudo-notch regardless of whether the Mac has a physical notch) or a floating
/// pill below the menu bar.
///
/// Deliberately two-valued, not three. The vendored `NookPresentation` offers an
/// `.auto` case that resolves per-screen, but Perch drops it: the same machine should
/// look the same regardless of which display it's plugged into, so users pick one of
/// the two concrete looks explicitly.
/// `Defaults.PreferRawRepresentable` is load-bearing, not decoration. Being both `Codable`
/// and `RawRepresentable` would otherwise make `Defaults` select
/// `RawRepresentableCodableBridge`, which is a *Codable* bridge: it persists the JSON
/// encoding (`"\"floating\""`, quotes included) rather than the bare raw string. That
/// format is awkward to write by hand, and `PreferencesMigration` has to do exactly that
/// when it carries `notchSimulationMode` over. Opting into the raw-value bridge keeps the
/// stored form a plain `"floating"` / `"notch"`.
enum IslandChromeStyle:
    String, Codable, CaseIterable, Sendable, Defaults.Serializable, Defaults.PreferRawRepresentable
{
    /// Pseudo-notch chrome (Atoll-style), used whether or not the display has a
    /// physical notch. The default.
    case notch
    /// A free-floating rounded pill just below the menu bar.
    case floating

    /// Localization key for the Settings picker. Reuses the keys the retired
    /// `NotchSimulationMode` published, minus the `.auto` case this type dropped.
    nonisolated var displayNameKey: String {
        switch self {
        case .notch: "settings.island_position.notch"
        case .floating: "settings.island_position.floating"
        }
    }

    /// Maps this style onto the vendored NookSurface's presentation intent.
    nonisolated var nookPresentation: NookPresentation {
        switch self {
        case .notch: .notch
        case .floating: .floating
        }
    }

    /// Migrates a persisted `NotchSimulationMode` raw value to the new two-valued
    /// style. `"auto"` and `"forceNotched"` both become `.notch` (matching the current
    /// default behavior on notched hardware and avoiding "the app suddenly looks
    /// different" for `.auto` users); `"forceNonNotched"` becomes `.floating`. An
    /// unrecognized raw value or a missing one (no prior preference stored) falls
    /// back to the `.notch` default.
    ///
    /// The three legacy raw values are literals rather than a live `NotchSimulationMode`
    /// enum: A5 deleted that type along with the rest of the pre-vendoring island layer,
    /// and keeping a whole `Defaults.Serializable` enum alive purely to feed one `switch`
    /// would have meant shipping a settings type nothing can select any more. What has to
    /// survive is the *strings already written to `UserDefaults` by shipped builds*, which
    /// is what these literals pin — see `PreferencesMigration.migrateIslandChromeStyle`.
    nonisolated static func migrating(fromLegacy legacyRawValue: String?) -> IslandChromeStyle {
        switch legacyRawValue {
        case "auto", "forceNotched": .notch
        case "forceNonNotched": .floating
        default: .notch
        }
    }
}
