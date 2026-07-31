import Foundation

enum AppVersion {
    static var displayString: String {
        displayString(infoDictionary: Bundle.main.infoDictionary)
    }

    nonisolated static func displayString(infoDictionary: [String: Any]?) -> String {
        let marketingVersion = infoDictionary?["CFBundleShortVersionString"] as? String
        let buildNumber = infoDictionary?["CFBundleVersion"] as? String

        return switch (marketingVersion, buildNumber) {
        case (.some(let version), .some(let build)):
            "\(version) (\(build))"
        case (.some(let version), .none):
            version
        case (.none, .some(let build)):
            build
        case (.none, .none):
            "—"
        }
    }
}
