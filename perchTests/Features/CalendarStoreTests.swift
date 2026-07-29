import Foundation
import Testing

@testable import perch

@Suite("CalendarStore")
struct CalendarStoreTests {
    // MARK: - normalizedTitle

    @Test("a real title passes through unchanged")
    func realTitlePassesThrough() {
        #expect(CalendarStore.normalizedTitle(from: "Standup") == "Standup")
    }

    @Test("nil title falls back to a placeholder")
    func nilTitleFallsBack() {
        #expect(CalendarStore.normalizedTitle(from: nil) == "Untitled Event")
    }

    @Test("whitespace-only title falls back to a placeholder")
    func whitespaceOnlyTitleFallsBack() {
        #expect(CalendarStore.normalizedTitle(from: "   \n  ") == "Untitled Event")
    }

    @Test("surrounding whitespace is trimmed")
    func surroundingWhitespaceIsTrimmed() {
        #expect(CalendarStore.normalizedTitle(from: "  Standup  ") == "Standup")
    }

    // MARK: - timeLabel

    @Test("all-day events show a fixed label regardless of start/end time")
    func allDayEventsShowFixedLabel() {
        let start = Date(timeIntervalSince1970: 0)
        let end = Date(timeIntervalSince1970: 3600)
        #expect(
            CalendarStore.timeLabel(startDate: start, endDate: end, isAllDay: true) == "All day")
    }

    @Test("timed events format as start – end in the given time zone")
    func timedEventsFormatAsRange() {
        let utc = TimeZone(identifier: "UTC")!
        // 2026-01-01 09:00 UTC and 10:30 UTC.
        let start = Date(timeIntervalSince1970: 1_767_258_000)
        let end = Date(timeIntervalSince1970: 1_767_263_400)
        #expect(
            CalendarStore.timeLabel(startDate: start, endDate: end, isAllDay: false, timeZone: utc)
                == "09:00 – 10:30")
    }
}
