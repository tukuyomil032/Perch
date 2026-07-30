// perchTests/NowPlaying/NowPlayingManagerTests.swift
import Testing

@testable import perch

@Suite("NowPlayingManager.matchesTerminatedApp")
@MainActor
struct NowPlayingManagerMatchesTerminatedAppTests {
    @Test("Spotify terminates only on its own bundle id")
    func spotifyMatchesOwnBundleId() {
        #expect(
            NowPlayingManager.matchesTerminatedApp(
                bundleID: "com.spotify.client", source: .spotify, sourceBundleIdentifier: nil
            ))
        #expect(
            !NowPlayingManager.matchesTerminatedApp(
                bundleID: "com.apple.Music", source: .spotify, sourceBundleIdentifier: nil
            ))
    }

    @Test("Apple Music terminates only on its own bundle id")
    func appleMusicMatchesOwnBundleId() {
        #expect(
            NowPlayingManager.matchesTerminatedApp(
                bundleID: "com.apple.Music", source: .appleMusic, sourceBundleIdentifier: nil
            ))
        #expect(
            !NowPlayingManager.matchesTerminatedApp(
                bundleID: "com.spotify.client", source: .appleMusic, sourceBundleIdentifier: nil
            ))
    }

    @Test("YouTube Music with a known sourceBundleIdentifier matches only that exact app")
    func youTubeMusicPrefersExactSourceBundleIdentifier() {
        // Kaset is running and playing; Chrome (also YTM-capable) quitting must NOT clear it.
        #expect(
            !NowPlayingManager.matchesTerminatedApp(
                bundleID: "com.google.Chrome",
                source: .youTubeMusic,
                sourceBundleIdentifier: "com.sertacozercan.Kaset"
            ))
        // Kaset itself quitting must clear it.
        #expect(
            NowPlayingManager.matchesTerminatedApp(
                bundleID: "com.sertacozercan.Kaset",
                source: .youTubeMusic,
                sourceBundleIdentifier: "com.sertacozercan.Kaset"
            ))
    }

    @Test("YouTube Music without a sourceBundleIdentifier falls back to list membership")
    func youTubeMusicFallsBackToListMembership() {
        #expect(
            NowPlayingManager.matchesTerminatedApp(
                bundleID: "com.sertacozercan.Kaset",
                source: .youTubeMusic,
                sourceBundleIdentifier: nil
            ))
        #expect(
            !NowPlayingManager.matchesTerminatedApp(
                bundleID: "com.spotify.client",
                source: .youTubeMusic,
                sourceBundleIdentifier: nil
            ))
    }

    @Test("MRMediaRemote source never matches a specific app termination")
    func mrMediaRemoteNeverMatches() {
        #expect(
            !NowPlayingManager.matchesTerminatedApp(
                bundleID: "com.apple.Music", source: .mrMediaRemote, sourceBundleIdentifier: nil
            ))
    }
}

@Suite("NowPlayingManager.resolveBundleIdentifier")
@MainActor
struct NowPlayingManagerResolveBundleIdentifierTests {
    @Test("nil bundleId is rejected")
    func nilBundleIdRejected() {
        #expect(
            NowPlayingManager.resolveBundleIdentifier(
                bundleId: nil, applicationName: nil, runningBundleIdentifiers: []
            ) == nil)
    }

    @Test("A known app reporting its own bundle id is accepted only while running")
    func ownBundleIdAcceptedOnlyWhileRunning() {
        #expect(
            NowPlayingManager.resolveBundleIdentifier(
                bundleId: "com.sertacozercan.Kaset", applicationName: nil,
                runningBundleIdentifiers: ["com.sertacozercan.Kaset"]
            ) == "com.sertacozercan.Kaset")
        #expect(
            NowPlayingManager.resolveBundleIdentifier(
                bundleId: "com.sertacozercan.Kaset", applicationName: nil,
                runningBundleIdentifiers: []
            ) == nil)
    }

    @Test("An unknown app's own bundle id is rejected")
    func unknownBundleIdRejected() {
        #expect(
            NowPlayingManager.resolveBundleIdentifier(
                bundleId: "com.apple.WebKit.Networking", applicationName: nil,
                runningBundleIdentifiers: []
            ) == nil)
    }

    @Test("A WebKit helper event resolves to the owning app's bundle id when applicationName matches exactly")
    func webKitHelperResolvesToKnownApp() {
        #expect(
            NowPlayingManager.resolveBundleIdentifier(
                bundleId: "com.apple.WebKit.GPU", applicationName: "Kaset",
                runningBundleIdentifiers: []
            ) == "com.sertacozercan.Kaset")
    }

    @Test("A WebKit helper event resolves via applicationName prefix match (real observed value)")
    func webKitHelperResolvesViaApplicationNamePrefix() {
        // Kaset's WebKit.GPU helper reports applicationName "Kaset Graphics and Media", not
        // "Kaset" verbatim — confirmed from a live device log. Must match by prefix, not equality.
        #expect(
            NowPlayingManager.resolveBundleIdentifier(
                bundleId: "com.apple.WebKit.GPU", applicationName: "Kaset Graphics and Media",
                runningBundleIdentifiers: []
            ) == "com.sertacozercan.Kaset")
    }

    @Test("A WebKit helper event from an unrecognized app (e.g. Mail) is rejected")
    func webKitHelperFromUnknownAppRejected() {
        #expect(
            NowPlayingManager.resolveBundleIdentifier(
                bundleId: "com.apple.WebKit.GPU", applicationName: "Mail",
                runningBundleIdentifiers: []
            ) == nil)
        #expect(
            NowPlayingManager.resolveBundleIdentifier(
                bundleId: "com.apple.WebKit.GPU", applicationName: nil,
                runningBundleIdentifiers: []
            ) == nil)
    }

    @Test("A WebKit helper event from Safari resolves to Safari's own bundle id")
    func webKitHelperFromSafariResolvesToSafari() {
        #expect(
            NowPlayingManager.resolveBundleIdentifier(
                bundleId: "com.apple.WebKit.GPU", applicationName: "Safari",
                runningBundleIdentifiers: []
            ) == "com.apple.Safari")
    }
}

@Suite("NowPlayingManager.isSameTrack")
struct NowPlayingManagerIsSameTrackTests {
    @Test("identical title and artist is the same track")
    func identicalTitleAndArtistIsSameTrack() {
        #expect(
            NowPlayingManager.isSameTrack(
                previousTitle: "Actor", previousArtist: "幾田りら",
                newTitle: "Actor", newArtist: "幾田りら"
            ))
    }

    @Test("a different title is a different track")
    func differentTitleIsDifferentTrack() {
        #expect(
            !NowPlayingManager.isSameTrack(
                previousTitle: "Actor", previousArtist: "幾田りら",
                newTitle: "IRIS OUT", newArtist: "幾田りら"
            ))
    }

    @Test("a different artist is a different track")
    func differentArtistIsDifferentTrack() {
        #expect(
            !NowPlayingManager.isSameTrack(
                previousTitle: "Actor", previousArtist: "幾田りら",
                newTitle: "Actor", newArtist: "米津玄師"
            ))
    }

    @Test("no previously-tracked title/artist is never the same track")
    func nilPreviousIsNeverSameTrack() {
        #expect(
            !NowPlayingManager.isSameTrack(
                previousTitle: nil, previousArtist: nil,
                newTitle: "Actor", newArtist: "幾田りら"
            ))
    }
}
