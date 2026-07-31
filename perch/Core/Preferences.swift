import Defaults
import Foundation

/// Persisted through `Defaults` rather than upstream's own JSON blob store — see the
/// modification note at the top of `ScreenLocator.swift`. The conformance lives here, not
/// in that file, so the vendored-adjacent source stays free of Perch's persistence choice.
extension ScreenPreference: Defaults.Serializable {}
extension UpdateChannel: Defaults.Serializable {}

extension Defaults.Keys {
    static let launchAtLogin = Key<Bool>("launchAtLogin", default: false)
    static let showInAllSpaces = Key<Bool>("showInAllSpaces", default: true)
    static let autoCollapseDelay = Key<Double>("autoCollapseDelay", default: 3.0)
    static let showNowPlayingSource = Key<Bool>("showNowPlayingSource", default: false)
    static let enableSpotify = Key<Bool>("enableSpotify", default: true)
    static let enableAppleMusic = Key<Bool>("enableAppleMusic", default: true)
    static let enableYouTubeMusic = Key<Bool>("enableYouTubeMusic", default: true)
    static let languageCode = Key<String>("languageCode", default: "en")
    static let updateChannel = Key<UpdateChannel>("updateChannel", default: .stable)
    static let aiRefreshInterval = Key<RefreshInterval>("aiRefreshInterval", default: .fiveMinutes)
    /// How the island chrome presents itself. Replaces `notchSimulationMode`; existing
    /// installs are migrated once at launch by `PreferencesMigration`.
    static let islandChromeStyle = Key<IslandChromeStyle>("islandChromeStyle", default: .notch)

    /// Rich (Atoll-inspired, default) vs Minimal (the original preset-driven widget list).
    static let uiMode = Key<UIMode>("uiMode", default: .rich)

    /// Which display the island lives on. Resolved through `ScreenLocator` and handed to
    /// the vendored surface as its `screenProvider`.
    static let islandScreenPreference = Key<ScreenPreference>(
        "islandScreenPreference", default: .default)
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
