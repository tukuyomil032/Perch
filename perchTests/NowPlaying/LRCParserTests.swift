// perchTests/NowPlaying/LRCParserTests.swift
import Testing

@testable import perch

@Suite("LRCParser")
@MainActor
struct LRCParserTests {
    @Test("standard LRC line parses correctly")
    func standardLineParsed() {
        let lrc = "[01:23.45] Hello world"
        let lines = LRCParser.parse(lrc)
        #expect(lines.count == 1)
        // 1m * 60 + 23 + 0.45 = 83.45
        #expect(abs(lines[0].timestamp - 83.45) < 0.01)
        #expect(lines[0].text == "Hello world")
    }

    @Test("millisecond precision (3 digits) parsed correctly")
    func threeDigitFracParsed() {
        let lrc = "[00:10.500] Song line"
        let lines = LRCParser.parse(lrc)
        #expect(lines.count == 1)
        #expect(abs(lines[0].timestamp - 10.5) < 0.001)
    }

    @Test("multiple lines sorted by timestamp")
    func multipleLinesSorted() {
        let lrc = "[02:00.00] Second\n[00:30.00] First\n[03:15.50] Third"
        let lines = LRCParser.parse(lrc)
        #expect(lines.count == 3)
        #expect(lines[0].text == "First")
        #expect(lines[1].text == "Second")
        #expect(lines[2].text == "Third")
    }

    @Test("empty text line is skipped")
    func emptyTextSkipped() {
        let lrc = "[00:10.00]\n[00:20.00] Valid"
        let lines = LRCParser.parse(lrc)
        #expect(lines.count == 1)
        #expect(lines[0].text == "Valid")
    }

    @Test("whitespace-only text line is skipped")
    func whitespaceOnlySkipped() {
        let lrc = "[00:10.00]   \n[00:20.00] Valid"
        let lines = LRCParser.parse(lrc)
        #expect(lines.count == 1)
    }

    @Test("invalid line format is skipped")
    func invalidFormatSkipped() {
        let lrc = "This is not LRC\n[00:05.00] Valid"
        let lines = LRCParser.parse(lrc)
        #expect(lines.count == 1)
        #expect(lines[0].text == "Valid")
    }

    @Test("empty string returns empty array")
    func emptyStringReturnsEmpty() {
        let lines = LRCParser.parse("")
        #expect(lines.isEmpty)
    }
}
