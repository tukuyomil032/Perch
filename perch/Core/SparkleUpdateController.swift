import Defaults
import Observation
import Sparkle

/// Owns Sparkle's updater and exposes the small, UI-safe surface used by Settings.
@MainActor
@Observable
final class SparkleUpdateController {
    @ObservationIgnored private let updaterController: SPUStandardUpdaterController
    @ObservationIgnored private let updaterDelegate: ChannelDelegate
    @ObservationIgnored private let isUpdaterStarted: Bool

    /// Sparkle starts only after `SUPublicEDKey` is configured in the app bundle.
    /// Starting without that key would allow an insecure configuration error instead
    /// of a usable update experience, so Settings leaves update checks unavailable until it is
    /// supplied in the app target's Info.plist.
    let isUpdateConfigurationReady: Bool

    var updateChannel: UpdateChannel {
        didSet {
            Defaults[.updateChannel] = updateChannel
            updaterDelegate.allowedChannels = updateChannel.allowedChannels
            if isUpdaterStarted {
                updaterController.updater.resetUpdateCycleAfterShortDelay()
            }
        }
    }

    init(startingUpdater: Bool = true) {
        let initialUpdateChannel = Defaults[.updateChannel]
        let updateConfigurationReady = SparkleUpdateConfiguration.isReady()
        updateChannel = initialUpdateChannel
        updaterDelegate = ChannelDelegate(allowedChannels: initialUpdateChannel.allowedChannels)
        isUpdateConfigurationReady = updateConfigurationReady
        isUpdaterStarted = startingUpdater && updateConfigurationReady
        updaterController = SPUStandardUpdaterController(
            startingUpdater: isUpdaterStarted,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: nil
        )
    }

    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    var canCheckForUpdates: Bool {
        isUpdaterStarted && updaterController.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}

enum SparkleUpdateConfiguration {
    nonisolated private static let publicKeyInfoKey = "SUPublicEDKey"

    nonisolated static func isReady(infoDictionary: [String: Any]? = Bundle.main.infoDictionary) -> Bool {
        guard let publicKey = infoDictionary?[publicKeyInfoKey] as? String else {
            return false
        }

        return !publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Sparkle retains its delegate weakly, so the controller keeps this object alive.
/// Sparkle invokes the delegate on its UI actor (the main thread).
@MainActor
private final class ChannelDelegate: NSObject, SPUUpdaterDelegate {
    var allowedChannels: Set<String>

    init(allowedChannels: Set<String>) {
        self.allowedChannels = allowedChannels
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        allowedChannels
    }
}
