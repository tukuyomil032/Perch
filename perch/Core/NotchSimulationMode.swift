import Defaults

enum NotchSimulationMode: String, CaseIterable, Defaults.Serializable {
    case auto
    case forceNotched
    case forceNonNotched

    var displayNameKey: String {
        switch self {
        case .auto: return "settings.island_position.auto"
        case .forceNotched: return "settings.island_position.notch"
        case .forceNonNotched: return "settings.island_position.floating"
        }
    }
}
