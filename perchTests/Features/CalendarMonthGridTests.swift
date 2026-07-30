import Foundation
import Testing

@testable import perch

private func utcCalendar(firstWeekday: Int = 1) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.firstWeekday = firstWeekday
    return calendar
}

private func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day))!
}

@Suite("CalendarMonthGrid")
struct CalendarMonthGridTests {
    @Test("every week has exactly 7 days")
    func fullWeeks() {
        let calendar = utcCalendar()
        let reference = date(2026, 7, 1, calendar: calendar)
        let grid = CalendarMonthGrid.build(referenceDate: reference, calendar: calendar)
        #expect(!grid.weeks.isEmpty)
        for week in grid.weeks {
            #expect(week.count == 7)
        }
    }

    @Test("leading/trailing days from adjacent months are marked out of month")
    func adjacentMonthDaysMarked() {
        // July 2026 starts on a Wednesday (UTC), so with a Sunday-first week the first
        // three cells belong to June.
        let calendar = utcCalendar(firstWeekday: 1)
        let reference = date(2026, 7, 15, calendar: calendar)
        let grid = CalendarMonthGrid.build(referenceDate: reference, calendar: calendar)

        let firstWeek = grid.weeks[0]
        let juneDays = firstWeek.filter { !$0.isInCurrentMonth }
        #expect(!juneDays.isEmpty)

        let julyDaysInFirstWeek = firstWeek.filter(\.isInCurrentMonth)
        #expect(julyDaysInFirstWeek.allSatisfy { $0.dayNumber >= 1 })
    }

    @Test("only the reference date is marked as today")
    func onlyReferenceDateIsToday() {
        let calendar = utcCalendar()
        let reference = date(2026, 7, 30, calendar: calendar)
        let grid = CalendarMonthGrid.build(referenceDate: reference, calendar: calendar)

        let todayCells = grid.weeks.flatMap { $0 }.filter(\.isToday)
        #expect(todayCells.count == 1)
        #expect(todayCells.first?.dayNumber == 30)
    }

    @Test("weekday symbols rotate to match firstWeekday")
    func weekdaySymbolsRotate() {
        let sundayFirst = utcCalendar(firstWeekday: 1)
        let mondayFirst = utcCalendar(firstWeekday: 2)
        let reference = date(2026, 7, 15, calendar: sundayFirst)

        let sundayGrid = CalendarMonthGrid.build(referenceDate: reference, calendar: sundayFirst)
        let mondayGrid = CalendarMonthGrid.build(referenceDate: reference, calendar: mondayFirst)

        #expect(sundayGrid.weekdaySymbols.first == "Sun")
        #expect(mondayGrid.weekdaySymbols.first == "Mon")
        #expect(sundayGrid.weekdaySymbols != mondayGrid.weekdaySymbols)
    }
}
