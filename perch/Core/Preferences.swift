import Defaults
import Foundation

extension Defaults.Keys {
    static let launchAtLogin = Key<Bool>("launchAtLogin", default: false)
    static let islandMode = Key<String>("islandMode", default: "auto")
    static let windowLevel = Key<String>("windowLevel", default: "statusBar+1")
    static let animationSpeed = Key<Double>("animationSpeed", default: 1.0)
    static let showInAllSpaces = Key<Bool>("showInAllSpaces", default: true)
    static let autoCollapseDelay = Key<Double>("autoCollapseDelay", default: 3.0)
    static let displayScreen = Key<Int>("displayScreen", default: -1)
    static let showNowPlayingSource = Key<Bool>("showNowPlayingSource", default: false)
    static let languageCode = Key<String>("languageCode", default: "en")
}
