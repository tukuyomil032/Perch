import Foundation

/// A month's worth of day cells laid out into calendar weeks, for `CalendarMonthColumn`'s
/// hover grid. Pure date math — no EventKit dependency, so it's trivially unit-testable
/// (mirrors `CalendarStore.timeLabel`/`normalizedTitle`, which are pure for the same reason).
nonisolated struct CalendarMonthGrid {
    struct Day: Identifiable, Equatable {
        let id: Date
        let dayNumber: Int
        let isInCurrentMonth: Bool
        let isToday: Bool
        let isSelected: Bool
    }

    let weekdaySymbols: [String]
    let weeks: [[Day]]

    /// Builds the grid for the month containing `referenceDate`, in `calendar`'s
    /// locale/firstWeekday. Always returns full 7-day weeks, padding with adjacent
    /// months' days (marked `isInCurrentMonth == false`) at both ends. `selectedDate`,
    /// if given, marks the one cell matching it as `isSelected` (Standalone Calendar's
    /// tappable day grid; `nil` when no selection applies, e.g. the compact hover grid).
    nonisolated static func build(
        referenceDate: Date,
        selectedDate: Date? = nil,
        calendar: Calendar = .current
    ) -> CalendarMonthGrid {
        let today = calendar.startOfDay(for: referenceDate)
        guard let monthInterval = calendar.dateInterval(of: .month, for: today) else {
            return CalendarMonthGrid(weekdaySymbols: rotatedWeekdaySymbols(calendar: calendar), weeks: [])
        }
        let monthStart = monthInterval.start
        let monthEndExclusive = monthInterval.end

        let leadingWeekday = calendar.component(.weekday, from: monthStart)
        let leadingOffset = (leadingWeekday - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -leadingOffset, to: monthStart)
        else {
            return CalendarMonthGrid(weekdaySymbols: rotatedWeekdaySymbols(calendar: calendar), weeks: [])
        }

        let daysInMonth = calendar.dateComponents([.day], from: monthStart, to: monthEndExclusive).day ?? 0
        let totalCells = Int(ceil(Double(leadingOffset + daysInMonth) / 7.0)) * 7

        var days: [Day] = []
        days.reserveCapacity(totalCells)
        for offset in 0..<totalCells {
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else { continue }
            let dayNumber = calendar.component(.day, from: date)
            let isInCurrentMonth = date >= monthStart && date < monthEndExclusive
            let isToday = calendar.isDate(date, inSameDayAs: today)
            let isSelected = selectedDate.map { calendar.isDate(date, inSameDayAs: $0) } ?? false
            days.append(
                Day(
                    id: date, dayNumber: dayNumber, isInCurrentMonth: isInCurrentMonth,
                    isToday: isToday, isSelected: isSelected))
        }

        let weeks = stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
        return CalendarMonthGrid(weekdaySymbols: rotatedWeekdaySymbols(calendar: calendar), weeks: weeks)
    }

    /// `Calendar.shortWeekdaySymbols` is always Sunday-first; rotate it to match
    /// `calendar.firstWeekday` so locales that start the week on Monday (etc.) get a
    /// header that matches the grid below it.
    private static func rotatedWeekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.shortWeekdaySymbols
        let startIndex = calendar.firstWeekday - 1
        return Array(symbols[startIndex...] + symbols[..<startIndex])
    }
}
