import SwiftUI

/// Rich mode's left column when nothing is playing: month header, hover for a full
/// month grid. Display-only — `store`'s fetch lifecycle belongs to the parent
/// (`AtollStyleExpandedView`), same pattern as `NowPlayingLyricsColumn`.
///
/// Doesn't show today's events — that's `TodayEventsColumn`'s job now that the two used
/// to live in one `CalendarWidget`.
struct CalendarMonthColumn: View {
    let store: CalendarStore
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if isHovering, store.authorizationState != .notDetermined {
                monthGridView
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .center)))
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(DesignSystem.cardPadding)
        .frame(maxHeight: .infinity, alignment: .top)
        .onHover { isHovering = $0 }
        .animation(DesignSystem.springAnimation, value: isHovering)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Self.monthYearFormatter.string(from: Date()))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(Self.dayFormatter.string(from: Date()))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private var monthGridView: some View {
        let grid = CalendarMonthGrid.build(referenceDate: Date())
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                ForEach(grid.weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(grid.weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(week) { day in
                        Text("\(day.dayNumber)")
                            .font(.system(size: 10, weight: day.isToday ? .bold : .regular))
                            .foregroundStyle(
                                day.isToday
                                    ? .white
                                    : day.isInCurrentMonth ? .white.opacity(0.6) : .white.opacity(0.2)
                            )
                            .frame(maxWidth: .infinity, minHeight: 18)
                            .background {
                                if day.isToday {
                                    Circle().fill(.white.opacity(0.18))
                                }
                            }
                    }
                }
            }
        }
    }

    private static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()
}
