import Defaults
import Foundation

enum PillBackgroundStyle: String, CaseIterable, Defaults.Serializable {
    case glassBlack
    case glassWhite
    var displayName: String {
        switch self {
        case .glassBlack: return "Glass Black"
        case .glassWhite: return "Glass White"
        }
    }
}

enum PillSizePreset: String, CaseIterable, Defaults.Serializable {
    case small, medium, large
    var pillWidth: CGFloat {
        switch self {
        case .small: 130
        case .medium: 150
        case .large: 170
        }
    }
    var pillHeight: CGFloat {
        switch self {
        case .small: 30
        case .medium: 34
        case .large: 38
        }
    }
    var musicCapsuleWidth: CGFloat { pillWidth - 42 }
    var displayName: String {
        switch self {
        case .small: "S"
        case .medium: "M"
        case .large: "L"
        }
    }
}

extension Defaults.Keys {
    static let launchAtLogin = Key<Bool>("launchAtLogin", default: false)
    static let islandMode = Key<String>("islandMode", default: "auto")
    static let windowLevel = Key<String>("windowLevel", default: "statusBar+1")
    static let animationSpeed = Key<Double>("animationSpeed", default: 1.0)
    static let showInAllSpaces = Key<Bool>("showInAllSpaces", default: true)
    static let autoCollapseDelay = Key<Double>("autoCollapseDelay", default: 3.0)
    static let displayScreen = Key<Int>("displayScreen", default: -1)
    static let showNowPlayingSource = Key<Bool>("showNowPlayingSource", default: false)
    static let enableSpotify = Key<Bool>("enableSpotify", default: true)
    static let enableAppleMusic = Key<Bool>("enableAppleMusic", default: true)
    static let enableYouTubeMusic = Key<Bool>("enableYouTubeMusic", default: true)
    static let languageCode = Key<String>("languageCode", default: "en")
    static let aiRefreshInterval = Key<RefreshInterval>("aiRefreshInterval", default: .fiveMinutes)
    static let notchSimulationMode = Key<NotchSimulationMode>("notchSimulationMode", default: .auto)
    static let pillSize = Key<PillSizePreset>("pillSize", default: .medium)
    static let showSatelliteCircle = Key<Bool>("showSatelliteCircle", default: false)
    static let pillBackgroundStyle = Key<PillBackgroundStyle>("pillBackgroundStyle", default: .glassBlack)
    static let claudeSessionTokenLimit = Key<Int>("claudeSessionTokenLimit", default: 88_000)
    static let claudeWeeklyTokenLimit = Key<Int>("claudeWeeklyTokenLimit", default: 500_000)
    static let claudeDailyTokenLimit = Key<Int>("claudeDailyTokenLimit", default: 88_000)

    // AI Usage 表示設定
    static let aiUsageShowRemaining = Key<Bool>("aiUsageShowRemaining", default: false)
    // false → "X% 使用" / true → "X% 残り"
    static let aiUsageAbsoluteResetTime = Key<Bool>("aiUsageAbsoluteResetTime", default: true)
    // true → "10:50 にリセット" / false → "リセット 2時間後"
    static let aiUsageShowPace = Key<Bool>("aiUsageShowPace", default: true)
    // ペース行（余裕% / 枯渇予測）の表示
    static let aiUsagePaceAbsoluteTime = Key<Bool>("aiUsagePaceAbsoluteTime", default: false)
    // 枯渇予測の形式: false → "あと 3h で枯渇" / true → "13:00 に枯渇"
}
