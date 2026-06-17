import Defaults

enum NotchSimulationMode: String, CaseIterable, Defaults.Serializable {
    case auto
    case forceNotched
    case forceNonNotched

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .forceNotched: return "Notch"
        case .forceNonNotched: return "Floating"
        }
    }
}
