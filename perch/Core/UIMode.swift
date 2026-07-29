import Defaults
import Foundation

/// Whether the expanded island shows the Atoll-inspired rich layout or the existing
/// preset-driven widget list.
///
/// `.rich` is the default: a fixed layout (now-playing activity + calendar, see
/// `AtollStyleExpandedView`) that does not expose preset switching — there is nothing to
/// switch between, since the layout is not preset-driven. `.minimal` keeps the original
/// `PresetTabBar` + `WidgetRegistry`-driven experience for users who prefer it.
enum UIMode: String, Codable, CaseIterable, Sendable, Defaults.Serializable, Defaults.PreferRawRepresentable {
    case rich
    case minimal

    nonisolated var displayNameKey: String {
        switch self {
        case .rich: "settings.ui_mode.rich"
        case .minimal: "settings.ui_mode.minimal"
        }
    }
}
