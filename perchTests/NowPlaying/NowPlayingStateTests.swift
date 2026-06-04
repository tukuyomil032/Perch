import AppKit
// perchTests/NowPlaying/NowPlayingStateTests.swift
import Testing

@testable import perch

@Suite("NowPlayingState")
@MainActor
struct NowPlayingStateTests {
    @Test("Valid dict with title returns state")
    func validDictParsed() {
        let dict: [String: Any] = [
            MRInfoKey.title: "Test Song",
            MRInfoKey.artist: "Test Artist",
            MRInfoKey.playbackRate: Double(1.0),
            MRInfoKey.duration: Double(240),
            MRInfoKey.elapsedTime: Double(60),
        ]
        let state = NowPlayingState(from: dict)
        #expect(state != nil)
        #expect(state?.title == "Test Song")
        #expect(state?.artist == "Test Artist")
        #expect(state?.isPlaying == true)
        #expect(state?.duration == 240)
        #expect(state?.elapsedTime == 60)
    }

    @Test("Missing title returns nil")
    func missingTitleReturnsNil() {
        let state = NowPlayingState(from: [MRInfoKey.artist: "Artist"])
        #expect(state == nil)
    }

    @Test("Nil dict returns nil")
    func nilDictReturnsNil() {
        let state = NowPlayingState(from: nil)
        #expect(state == nil)
    }

    @Test("playbackRate 0 means not playing")
    func playbackRateZeroNotPlaying() {
        let dict: [String: Any] = [
            MRInfoKey.title: "Paused Song",
            MRInfoKey.playbackRate: Double(0.0),
        ]
        let state = NowPlayingState(from: dict)
        #expect(state?.isPlaying == false)
    }

    @Test("progress computed correctly")
    func progressComputed() {
        let dict: [String: Any] = [
            MRInfoKey.title: "Song",
            MRInfoKey.duration: Double(200),
            MRInfoKey.elapsedTime: Double(50),
        ]
        let state = NowPlayingState(from: dict)
        #expect(state?.progress == 0.25)
    }

    @Test("progress is 0 when no duration")
    func progressZeroWithNoDuration() {
        let dict: [String: Any] = [MRInfoKey.title: "Song"]
        let state = NowPlayingState(from: dict)
        #expect(state?.progress == 0)
    }

    @Test("progress clamps to 1 when elapsed exceeds duration")
    func progressClamped() {
        let dict: [String: Any] = [
            MRInfoKey.title: "Song",
            MRInfoKey.duration: Double(100),
            MRInfoKey.elapsedTime: Double(120),
        ]
        #expect(NowPlayingState(from: dict)?.progress == 1.0)
    }

    @Test("formattedDuration formats seconds correctly")
    func formattedDurationFormatted() {
        let dict: [String: Any] = [
            MRInfoKey.title: "Song",
            MRInfoKey.duration: Double(240),
        ]
        #expect(NowPlayingState(from: dict)?.formattedDuration == "4:00")
    }
}
