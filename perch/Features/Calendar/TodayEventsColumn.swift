import SwiftUI

/// Rich mode's center column when there's no now-playing content to show (no music, or
/// music with no lyrics): today's calendar events, or the calendar permission state.
/// Display-only — `store`'s fetch lifecycle belongs to the parent
/// (`AtollStyleExpandedView`), same pattern as `NowPlayingLyricsColumn`.
struct TodayEventsColumn: View {
    let store: CalendarStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding(DesignSystem.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var content: some View {
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
}
