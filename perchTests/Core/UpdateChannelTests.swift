import Testing

@testable import perch

@Suite("UpdateChannel")
struct UpdateChannelTests {
    @Test("stable accepts only the default appcast channel")
    func stableAllowsOnlyDefaultChannel() {
        #expect(UpdateChannel.stable.allowedChannels == [])
    }

    @Test("beta accepts beta appcast items")
    func betaAllowsBetaChannel() {
        #expect(UpdateChannel.beta.allowedChannels == ["beta"])
    }

    @Test("raw values round-trip")
    func rawValuesRoundTrip() {
        for channel in UpdateChannel.allCases {
            #expect(UpdateChannel(rawValue: channel.rawValue) == channel)
        }
    }

    @Test("requires a nonempty Sparkle public key")
    func requiresPublicKey() {
        #expect(!SparkleUpdateConfiguration.isReady(infoDictionary: nil))
        #expect(!SparkleUpdateConfiguration.isReady(infoDictionary: ["SUPublicEDKey": "  "]))
        #expect(SparkleUpdateConfiguration.isReady(infoDictionary: ["SUPublicEDKey": "public-key"]))
    }
}
