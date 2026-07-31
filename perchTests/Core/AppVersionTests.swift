import Testing

@testable import perch

@Suite("AppVersion")
struct AppVersionTests {
    @Test("formats marketing version and build number")
    func formatsVersionAndBuild() {
        #expect(
            AppVersion.displayString(infoDictionary: [
                "CFBundleShortVersionString": "0.36.0",
                "CFBundleVersion": "42",
            ]) == "0.36.0 (42)")
    }

    @Test("uses the available version value when one key is absent")
    func formatsPartialInfo() {
        #expect(AppVersion.displayString(infoDictionary: ["CFBundleShortVersionString": "0.36.0"]) == "0.36.0")
        #expect(AppVersion.displayString(infoDictionary: ["CFBundleVersion": "42"]) == "42")
    }

    @Test("uses a placeholder when version information is unavailable")
    func formatsMissingInfo() {
        #expect(AppVersion.displayString(infoDictionary: nil) == "—")
    }
}
