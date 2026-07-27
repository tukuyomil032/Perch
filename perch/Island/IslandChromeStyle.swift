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
enum IslandChromeStyle: String, Codable, CaseIterable, Sendable, Defaults.Serializable {
    /// Pseudo-notch chrome (Atoll-style), used whether or not the display has a
    /// physical notch. The default.
    case notch
    /// A free-floating rounded pill just below the menu bar.
    case floating

    /// Maps this style onto the vendored NookSurface's presentation intent.
    nonisolated var nookPresentation: NookPresentation {
        switch self {
        case .notch: .notch
        case .floating: .floating
        }
    }

    /// Migrates a persisted `NotchSimulationMode` raw value to the new two-valued
    /// style. `.auto` and `.forceNotched` both become `.notch` (matching the current
    /// default behavior on notched hardware and avoiding "the app suddenly looks
    /// different" for `.auto` users); `.forceNonNotched` becomes `.floating`. An
    /// unrecognized raw value or a missing one (no prior preference stored) falls
    /// back to the `.notch` default.
    nonisolated static func migrating(fromLegacy legacyRawValue: String?) -> IslandChromeStyle {
        guard
            let legacyRawValue,
            let legacy = NotchSimulationMode(rawValue: legacyRawValue)
        else {
            return .notch
        }

        switch legacy {
        case .auto, .forceNotched: return .notch
        case .forceNonNotched: return .floating
        }
    }
}
