import Foundation
// perchTests/Providers/ClaudeUsageMergerTests.swift
import Testing

@testable import perch

@Suite("ClaudeUsageMerger")
@MainActor
struct ClaudeUsageMergerTests {
    private func makeLimits(usedFraction: Double = 0.5) -> ClaudeLimitUsage {
        ClaudeLimitUsage(
            session: UsageWindow(usedFraction: usedFraction, resetsAt: nil),
            weekly: UsageWindow(usedFraction: usedFraction * 0.5, resetsAt: nil),
            routines: nil,
            planName: "Pro")
    }

    private func makeLocalUsage(todayCost: Double = 1.5) -> ClaudeLocalUsage {
        ClaudeLocalUsage(
            todayTokens: 10_000, thirtyDayTokens: 200_000,
            todayCostUSD: todayCost, thirtyDayCostUSD: todayCost * 10,
            dailyUsage: [], modelBreakdown: [])
    }

    @Test("success + success yields session + cost data")
    func bothSuccessYieldsFullData() {
        let data = ClaudeUsageMerger.merge(
            remote: .success(makeLimits()),
            local: .success(makeLocalUsage()))
        #expect(data.session != nil)
        #expect(data.weekly != nil)
        #expect(data.cost != nil)
        #expect(data.cost?.todayUSD == 1.5)
        #expect(data.planName == "Pro")
        #expect(data.warningMessage == nil)
    }

    @Test("success remote + failure local sets warning, preserves limits")
    func remoteSuccessLocalFailure() {
        let data = ClaudeUsageMerger.merge(
            remote: .success(makeLimits()),
            local: .failure(.localParsing(NSError(domain: "test", code: 1))))
        #expect(data.session != nil)
        #expect(data.cost == nil)
        #expect(data.warningMessage != nil)
    }

    @Test("failure remote + success local sets warning, preserves cost")
    func remoteFailureLocalSuccess() {
        let data = ClaudeUsageMerger.merge(
            remote: .failure(.unauthorized),
            local: .success(makeLocalUsage(todayCost: 2.0)))
        #expect(data.session == nil)
        #expect(data.cost?.todayUSD == 2.0)
        #expect(data.warningMessage != nil)
    }

    @Test("both failure returns empty data with warning")
    func bothFailureReturnsWarning() {
        let data = ClaudeUsageMerger.merge(
            remote: .failure(.missingCredential),
            local: .failure(.missingCredential))
        #expect(data.session == nil)
        #expect(data.cost == nil)
        #expect(data.warningMessage != nil)
        #expect(!(data.warningMessage!.isEmpty))
    }

    @Test("planName falls back to Claude Code when remote has none")
    func planNameFallback() {
        let limitsNoName = ClaudeLimitUsage(
            session: nil, weekly: nil, routines: nil, planName: nil)
        let data = ClaudeUsageMerger.merge(
            remote: .success(limitsNoName),
            local: .failure(.missingCredential))
        #expect(data.planName == "Claude Code")
    }
}
