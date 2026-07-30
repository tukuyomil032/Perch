import Defaults
import Foundation
import Testing

@testable import perch

@Suite("UIMode")
struct UIModeTests {
    @Test("rich is the default persisted value")
    func richIsTheDefault() {
        #expect(Defaults.Keys.uiMode.defaultValue == .rich)
    }

    @Test("every case has a distinct display name key")
    func displayNameKeysAreDistinct() {
        let keys = Set(UIMode.allCases.map(\.displayNameKey))
        #expect(keys.count == UIMode.allCases.count)
    }

    @Test("display name keys are namespaced under settings.ui_mode")
    func displayNameKeysAreNamespaced() {
        for mode in UIMode.allCases {
            #expect(mode.displayNameKey.hasPrefix("settings.ui_mode."))
        }
    }
}
