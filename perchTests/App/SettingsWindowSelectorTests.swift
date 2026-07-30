import Foundation
import Testing

@testable import perch

@Suite("SettingsWindowSelector")
struct SettingsWindowSelectorTests {
    @Test("skips a keyable+visible chrome window and picks the real target after it")
    func skipsChrome() {
        let candidates = [
            SettingsWindowSelector.Candidate(canBecomeKey: true, isVisible: true, isChrome: true),
            SettingsWindowSelector.Candidate(canBecomeKey: true, isVisible: true, isChrome: false),
        ]
        #expect(SettingsWindowSelector.selectTarget(from: candidates) == 1)
    }

    @Test("returns nil when only chrome windows are present")
    func nilWhenOnlyChrome() {
        let candidates = [
            SettingsWindowSelector.Candidate(canBecomeKey: true, isVisible: true, isChrome: true)
        ]
        #expect(SettingsWindowSelector.selectTarget(from: candidates) == nil)
    }

    @Test("ignores non-visible non-chrome windows")
    func ignoresHidden() {
        let candidates = [
            SettingsWindowSelector.Candidate(canBecomeKey: true, isVisible: false, isChrome: false),
            SettingsWindowSelector.Candidate(canBecomeKey: true, isVisible: true, isChrome: false),
        ]
        #expect(SettingsWindowSelector.selectTarget(from: candidates) == 1)
    }

    @Test("picks the first eligible candidate when multiple exist")
    func picksFirstEligible() {
        let candidates = [
            SettingsWindowSelector.Candidate(canBecomeKey: true, isVisible: true, isChrome: false),
            SettingsWindowSelector.Candidate(canBecomeKey: true, isVisible: true, isChrome: false),
        ]
        #expect(SettingsWindowSelector.selectTarget(from: candidates) == 0)
    }
}
