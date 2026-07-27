import Foundation
import Testing

@testable import perch

/// `ScreenLocator` is mostly a thin `NSScreen` wrapper (`displayID(for:)`,
/// `uuid(for:)`, `connectedDisplays()`, `builtInScreen()`), which needs a live display
/// arrangement and can't be exercised meaningfully in a headless test run. The one part
/// carved out as pure policy - by design, per its doc comment - is
/// `resolveIndex(preference:displays:mainIndex:)`, which takes plain `DisplayCandidate`
/// values instead of `NSScreen`. These tests cover that fallback-chain policy.
struct ScreenLocatorTests {

    private let builtIn = ScreenLocator.DisplayCandidate(uuid: "builtin-uuid", isBuiltIn: true)
    private let external = ScreenLocator.DisplayCandidate(uuid: "external-uuid", isBuiltIn: false)
    private let externalNoUUID = ScreenLocator.DisplayCandidate(uuid: nil, isBuiltIn: false)

    // MARK: - Empty displays

    @Test func resolveIndex_emptyDisplays_returnsNil() {
        let index = ScreenLocator.resolveIndex(
            preference: .builtIn,
            displays: [],
            mainIndex: nil
        )
        #expect(index == nil)
    }

    // MARK: - .builtIn mode

    @Test func resolveIndex_builtIn_prefersBuiltInDisplay() {
        let index = ScreenLocator.resolveIndex(
            preference: .builtIn,
            displays: [external, builtIn],
            mainIndex: 0
        )
        #expect(index == 1)
    }

    @Test func resolveIndex_builtIn_fallsBackToMainWhenNoBuiltIn() {
        let index = ScreenLocator.resolveIndex(
            preference: .builtIn,
            displays: [external, externalNoUUID],
            mainIndex: 1
        )
        #expect(index == 1)
    }

    @Test func resolveIndex_builtIn_fallsBackToFirstWhenNoBuiltInOrMain() {
        let index = ScreenLocator.resolveIndex(
            preference: .builtIn,
            displays: [external, externalNoUUID],
            mainIndex: nil
        )
        #expect(index == 0)
    }

    // MARK: - .main mode

    @Test func resolveIndex_main_prefersMainIndex() {
        let index = ScreenLocator.resolveIndex(
            preference: .main,
            displays: [builtIn, external],
            mainIndex: 1
        )
        #expect(index == 1)
    }

    @Test func resolveIndex_main_fallsBackToBuiltInWhenMainUnknown() {
        let index = ScreenLocator.resolveIndex(
            preference: .main,
            displays: [external, builtIn],
            mainIndex: nil
        )
        #expect(index == 1)
    }

    @Test func resolveIndex_main_fallsBackToFirstWhenNoMainOrBuiltIn() {
        let index = ScreenLocator.resolveIndex(
            preference: .main,
            displays: [external, externalNoUUID],
            mainIndex: nil
        )
        #expect(index == 0)
    }

    // MARK: - .specific mode

    @Test func resolveIndex_specific_matchesUUID() {
        let index = ScreenLocator.resolveIndex(
            preference: .specific("external-uuid"),
            displays: [builtIn, external],
            mainIndex: 0
        )
        #expect(index == 1)
    }

    @Test func resolveIndex_specific_degradesToBuiltInWhenUUIDNotFound() {
        let index = ScreenLocator.resolveIndex(
            preference: .specific("missing-uuid"),
            displays: [external, builtIn],
            mainIndex: 0
        )
        #expect(index == 1)
    }

    @Test func resolveIndex_specific_degradesToMainWhenUUIDNotFoundAndNoBuiltIn() {
        let index = ScreenLocator.resolveIndex(
            preference: .specific("missing-uuid"),
            displays: [external, externalNoUUID],
            mainIndex: 1
        )
        #expect(index == 1)
    }

    @Test func resolveIndex_specific_degradesToFirstWhenNothingMatches() {
        let index = ScreenLocator.resolveIndex(
            preference: .specific("missing-uuid"),
            displays: [external, externalNoUUID],
            mainIndex: nil
        )
        #expect(index == 0)
    }

    // MARK: - ScreenPreference decode leniency

    @Test func screenPreference_decode_unrecognizedMode_fallsBackToDefault() throws {
        let json = #"{"mode":"unknownFutureMode"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ScreenPreference.self, from: json)
        #expect(decoded == .default)
    }

    @Test func screenPreference_decode_specificWithoutUUID_fallsBackToDefault() throws {
        let json = #"{"mode":"specific"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ScreenPreference.self, from: json)
        #expect(decoded == .default)
    }

    @Test func screenPreference_roundTrip_specificPreservesUUID() throws {
        let original = ScreenPreference.specific("some-uuid")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ScreenPreference.self, from: data)
        #expect(decoded == original)
    }
}
