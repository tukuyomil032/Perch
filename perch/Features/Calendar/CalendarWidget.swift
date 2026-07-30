import SwiftUI

/// Rich mode's calendar panel: today's date, and either the day's events or a
/// "nothing scheduled" placeholder. Not a `PerchWidget` — Rich mode is a fixed layout,
/// not a preset-driven one, so there's no registry slot for this to occupy.
struct CalendarWidget: View {
    @State private var store = CalendarStore()
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
        }
        .padding(DesignSystem.cardPadding)
        .task {
            await store.requestAccessAndRefresh()
        }
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

    @ViewBuilder
    private var content: some View {
        if isHovering, store.authorizationState != .notDetermined {
            monthGridView
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .center)))
        } else {
            simpleContent
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var simpleContent: some View {
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
            if store.todayEvents.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("No events today")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("Enjoy your free time.")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(store.todayEvents.prefix(4)) { event in
                        eventRow(event)
                    }
                }
            }
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

    private func eventRow(_ event: CalendarEvent) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.white.opacity(0.3))
                .frame(width: 5, height: 5)
            Text(event.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(
                CalendarStore.timeLabel(
                    startDate: event.startDate, endDate: event.endDate, isAllDay: event.isAllDay)
            )
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(.white.opacity(0.4))
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
