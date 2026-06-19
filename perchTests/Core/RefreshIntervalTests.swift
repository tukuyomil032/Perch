// perchTests/Core/RefreshIntervalTests.swift
import Testing

@testable import perch

@Suite("RefreshInterval")
@MainActor
struct RefreshIntervalTests {
    @Test("oneMinute is 60 seconds")
    func oneMinuteIs60() {
        #expect(RefreshInterval.oneMinute.timeInterval == 60)
    }

    @Test("fiveMinutes is 300 seconds")
    func fiveMinutesIs300() {
        #expect(RefreshInterval.fiveMinutes.timeInterval == 300)
    }

    @Test("fifteenMinutes is 900 seconds")
    func fifteenMinutesIs900() {
        #expect(RefreshInterval.fifteenMinutes.timeInterval == 900)
    }

    @Test("manual returns nil")
    func manualReturnsNil() {
        #expect(RefreshInterval.manual.timeInterval == nil)
    }

    @Test("rawValue round-trips for all cases")
    func rawValueRoundTrip() {
        for interval in RefreshInterval.allCases {
            #expect(RefreshInterval(rawValue: interval.rawValue) == interval)
        }
    }
}
