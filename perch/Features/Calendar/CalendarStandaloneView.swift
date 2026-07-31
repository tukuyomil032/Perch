import SwiftUI

/// Rich mode's Home layout when nothing is playing — replaces the left/center column
/// pair entirely rather than just standing in for the left one, per
/// docs/macOS-Expanded-Surface-Layout-Handbook-ja.md §13 ("Standalone Calendar"): a
/// month grid (with day tap-to-select) on the left, the selected day's events on the
/// right. Display-only — `store`'s fetch lifecycle belongs to the parent
/// (`RichHomeView`), same pattern as `NowPlayingLyricsColumn`.
///
/// Supersedes the old `CalendarMonthColumn` (hover-to-reveal grid, today-only
/// highlight, no selection) — that shape only made sense as a narrow column sharing
/// space with `NowPlayingCard`; here the calendar owns the whole row.
struct CalendarStandaloneView: View {
    let store: CalendarStore
    @State private var displayedMonth = Date()

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 12
            let paneWidth = max((proxy.size.width - spacing) / 2, 0)
            HStack(alignment: .top, spacing: spacing) {
                monthPane
                    .frame(width: paneWidth)
                eventsPane
                    .frame(width: paneWidth)
            }
        }
        .padding(DesignSystem.cardPadding)
    }

    // MARK: - Left: month grid

    private var monthPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            monthHeader
            weekdayHeader
            grid
        }
    }

    private var monthHeader: some View {
        HStack(spacing: 6) {
            Text(Self.monthYearFormatter.string(from: displayedMonth))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            monthNavButton(systemName: "chevron.left") { changeMonth(by: -1) }
            monthNavButton(systemName: "chevron.right") { changeMonth(by: 1) }
        }
    }

    private func monthNavButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 6) {
            ForEach(monthGrid.weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        VStack(spacing: 6) {
            ForEach(Array(monthGrid.weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 6) {
                    ForEach(week) { day in
                        dayCell(day)
                    }
                }
            }
        }
    }

    private func dayCell(_ day: CalendarMonthGrid.Day) -> some View {
        Button {
            Task { await store.selectDate(day.id) }
        } label: {
            Text("\(day.dayNumber)")
                .font(.system(size: 11, weight: day.isToday ? .bold : .regular))
                .foregroundStyle(
                    day.isSelected
                        ? .white
                        : day.isInCurrentMonth ? .white.opacity(0.7) : .white.opacity(0.25)
                )
                .frame(width: 28, height: 28)
                .background {
                    if day.isSelected {
                        Circle().fill(.white.opacity(0.22))
                    } else if day.isToday {
                        Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private var monthGrid: CalendarMonthGrid {
        CalendarMonthGrid.build(referenceDate: displayedMonth, selectedDate: store.selectedDate)
    }

    private func changeMonth(by delta: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: delta, to: displayedMonth)
        else { return }
        displayedMonth = next
    }

    // MARK: - Right: selected day's events

    private var eventsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                eventsContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var eventsContent: some View {
        switch store.authorizationState {
        case .notDetermined:
            ProgressView()
                .controlSize(.small)
        case .denied:
            VStack(alignment: .leading, spacing: 4) {
                Text("Calendar access denied")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                Text("Enable it in System Settings › Privacy & Security › Calendars.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
            }
        case .authorized:
            if store.selectedDateEvents.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("No events")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("Nothing scheduled this day.")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                }
            } else {
                ForEach(store.selectedDateEvents) { event in
                    eventCard(event)
                }
            }
        }
    }

    private func eventCard(_ event: CalendarEvent) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(eventColor(event))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                Text(
                    CalendarStore.timeLabel(
                        startDate: event.startDate, endDate: event.endDate, isAllDay: event.isAllDay)
                )
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .frame(minWidth: 44, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(minHeight: 50)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.05))
        }
    }

    private func eventColor(_ event: CalendarEvent) -> Color {
        guard let color = event.color else { return .white.opacity(0.3) }
        return Color(red: color.red, green: color.green, blue: color.blue)
    }

    private static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
}
