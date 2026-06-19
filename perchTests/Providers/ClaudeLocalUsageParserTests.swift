import Foundation
// perchTests/Providers/ClaudeLocalUsageParserTests.swift
import Testing

@testable import perch

@Suite("ClaudeLocalUsageParser")
@MainActor
struct ClaudeLocalUsageParserTests {
    private func makeTestDir() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("perch-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    private func isoDate(secondsAgo: TimeInterval = 3600) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date().addingTimeInterval(-secondsAgo))
    }

    private func makeEntry(
        msgId: String = "msg_001",
        requestId: String = "req_abc",
        model: String = "claude-sonnet-4-6",
        inputTokens: Int = 100,
        outputTokens: Int = 50,
        secondsAgo: TimeInterval = 3600,
        costUSD: Double? = nil
    ) -> String {
        var costPart = ""
        if let c = costUSD { costPart = #","costUSD":\#(c)"# }
        return
            #"{"type":"assistant","requestId":"\#(requestId)"\#(costPart),"timestamp":"\#(isoDate(secondsAgo: secondsAgo))","message":{"id":"\#(msgId)","model":"\#(model)","usage":{"input_tokens":\#(inputTokens),"output_tokens":\#(outputTokens),"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}"#
    }

    @Test("missing directory returns zero usage")
    func missingDirectoryReturnsZero() throws {
        let dir = URL(fileURLWithPath: "/nonexistent/path/\(UUID())")
        let result = try ClaudeLocalUsageParser.parseUsage(in: dir)
        #expect(result.todayTokens == 0)
        #expect(result.thirtyDayTokens == 0)
        #expect(result.todayCostUSD == 0)
    }

    @Test("empty directory returns zero usage")
    func emptyDirectoryReturnsZero() throws {
        let dir = try makeTestDir()
        defer { cleanup(dir) }
        let result = try ClaudeLocalUsageParser.parseUsage(in: dir)
        #expect(result.todayTokens == 0)
    }

    @Test("single assistant entry counted in today and 30-day")
    func singleEntryCountedInBoth() throws {
        let dir = try makeTestDir()
        defer { cleanup(dir) }
        let entry = makeEntry(inputTokens: 1000, outputTokens: 500)
        try entry.write(
            to: dir.appendingPathComponent("session.jsonl"),
            atomically: true, encoding: .utf8)
        let result = try ClaudeLocalUsageParser.parseUsage(in: dir)
        // todayTokens = 1000 + 500 + 0 (cache) = 1500
        #expect(result.todayTokens == 1500)
        #expect(result.thirtyDayTokens == 1500)
    }

    @Test("precomputed costUSD used instead of calculated")
    func precomputedCostUsed() throws {
        let dir = try makeTestDir()
        defer { cleanup(dir) }
        let entry = makeEntry(inputTokens: 100, outputTokens: 50, costUSD: 9.99)
        try entry.write(
            to: dir.appendingPathComponent("session.jsonl"),
            atomically: true, encoding: .utf8)
        let result = try ClaudeLocalUsageParser.parseUsage(in: dir)
        #expect(abs(result.todayCostUSD - 9.99) < 0.001)
    }

    @Test("duplicate composite key entries are deduplicated")
    func duplicateEntriesDeduplicated() throws {
        let dir = try makeTestDir()
        defer { cleanup(dir) }
        let entry = makeEntry(
            msgId: "msg_dup", requestId: "req_dup",
            inputTokens: 100, outputTokens: 50)
        let content = entry + "\n" + entry
        try content.write(
            to: dir.appendingPathComponent("session.jsonl"),
            atomically: true, encoding: .utf8)
        let result = try ClaudeLocalUsageParser.parseUsage(in: dir)
        // 100+50=150, not doubled
        #expect(result.todayTokens == 150)
    }

    @Test("non-assistant type entries are ignored")
    func nonAssistantIgnored() throws {
        let dir = try makeTestDir()
        defer { cleanup(dir) }
        let userEntry =
            #"{"type":"user","timestamp":"\#(isoDate())","message":{"id":"msg_u","model":"claude-sonnet-4-6","usage":{"input_tokens":999,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}"#
        try userEntry.write(
            to: dir.appendingPathComponent("session.jsonl"),
            atomically: true, encoding: .utf8)
        let result = try ClaudeLocalUsageParser.parseUsage(in: dir)
        #expect(result.todayTokens == 0)
    }

    @Test("entry older than 30 days excluded from totals")
    func oldEntryExcluded() throws {
        let dir = try makeTestDir()
        defer { cleanup(dir) }
        let old = makeEntry(
            msgId: "msg_old", requestId: "req_old",
            inputTokens: 500, outputTokens: 200,
            secondsAgo: 31 * 24 * 3600)
        try old.write(
            to: dir.appendingPathComponent("old.jsonl"),
            atomically: true, encoding: .utf8)
        let result = try ClaudeLocalUsageParser.parseUsage(in: dir)
        #expect(result.thirtyDayTokens == 0)
    }
}
