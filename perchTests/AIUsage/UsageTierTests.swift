import Foundation
// perchTests/AIUsage/UsageTierTests.swift
import Testing

@testable import perch

@Suite("UsageTier")
@MainActor
struct UsageTierTests {
    private func makeTier(usedFraction: Double) -> UsageTier {
        UsageTier(
            usedFraction: usedFraction, resetsAt: nil, label: "Test",
            source: .localEstimate, periodDuration: nil)
    }

    @Test("remainingFraction is 1 - usedFraction")
    func remainingFraction() {
        let tier = makeTier(usedFraction: 0.4)
        #expect(abs(tier.remainingFraction - 0.6) < 0.001)
    }

    @Test("remainingFraction clamps to 0 when over 100%")
    func remainingFractionClamp() {
        let tier = makeTier(usedFraction: 1.5)
        #expect(tier.remainingFraction == 0)
    }

    @Test("usedPercent rounds correctly")
    func usedPercent() {
        let tier = makeTier(usedFraction: 0.754)
        #expect(tier.usedPercent == 75)
    }

    @Test("remainingPercent + usedPercent = 100 for normal range")
    func percentsSum100() {
        let tier = makeTier(usedFraction: 0.3)
        #expect(tier.usedPercent + tier.remainingPercent == 100)
    }

    @Test("paceInfo returns nil when resetsAt is nil")
    func paceInfoNilWhenNoResetsAt() {
        let tier = makeTier(usedFraction: 0.5)
        #expect(tier.paceInfo() == nil)
    }

    @Test("paceInfo returns nil when elapsed is under 60s")
    func paceInfoNilWhenShortElapsed() {
        // period=3601s, resetsAt in 3600s → elapsed = 3601 - 3600 = 1s < 60 → nil
        let tier = UsageTier(
            usedFraction: 0.5,
            resetsAt: Date().addingTimeInterval(3600),
            label: "Test", source: .localEstimate,
            periodDuration: 3601)
        #expect(tier.paceInfo() == nil)
    }

    @Test("paceInfo willSurvive when on-pace")
    func paceInfoWillSurvive() {
        // 5h period, 50% used at 2.5h elapsed → projected = exactly 100% → willSurvive
        let now = Date()
        let period: TimeInterval = 5 * 3600
        let elapsed: TimeInterval = 2.5 * 3600
        let tier = UsageTier(
            usedFraction: 0.5,
            resetsAt: now.addingTimeInterval(period - elapsed),
            label: "Session", source: .anthropicOAuth,
            periodDuration: period)
        let pace = tier.paceInfo(now: now)
        #expect(pace != nil)
        #expect(pace!.willSurvive)
    }

    @Test("paceInfo exhaustionDate set when over-pace")
    func paceInfoOverPaceHasExhaustionDate() {
        // 5h period, 90% used in 1h → will exceed budget
        let now = Date()
        let period: TimeInterval = 5 * 3600
        let elapsed: TimeInterval = 1 * 3600
        let tier = UsageTier(
            usedFraction: 0.9,
            resetsAt: now.addingTimeInterval(period - elapsed),
            label: "Session", source: .anthropicOAuth,
            periodDuration: period)
        let pace = tier.paceInfo(now: now)
        #expect(pace != nil)
        #expect(!pace!.willSurvive)
        #expect(pace!.exhaustionDate != nil)
    }
}
