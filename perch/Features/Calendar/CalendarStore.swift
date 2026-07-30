import EventKit
import Foundation

/// A single event as `CalendarStore` presents it — decoupled from `EKEvent` so the
/// widget (and its tests) don't need to touch EventKit directly.
struct CalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let color: EventColor?

    /// RGB components rather than `NSColor`/`CGColor` directly — those aren't
    /// `Equatable` in a way that's convenient to carry through `@Observable` state
    /// and construct in tests.
    struct EventColor: Equatable {
        let red: Double
        let green: Double
        let blue: Double
    }
}

/// Fetches today's calendar events via EventKit, holding the authorization flow and the
/// fetch behind one `@Observable` store.
///
/// EventKit access is deliberately a real permission prompt — unlike the system status
/// cluster's battery/Wi-Fi (see `docs/opennook-migration-plan.md` B-3, "zero permission
/// dialogs"), the calendar widget is a feature the user explicitly asked for, so asking
/// once for it is legitimate rather than something to engineer around.
@MainActor
@Observable
final class CalendarStore {
    enum AuthorizationState: Equatable {
        case notDetermined
        case authorized
        case denied
    }

    private(set) var authorizationState: AuthorizationState
    private(set) var todayEvents: [CalendarEvent] = []

    /// The day `selectedDateEvents` was fetched for — Standalone Calendar's right pane
    /// (`CalendarStandaloneView`). Defaults to today; `selectDate(_:)` moves it when the
    /// user taps a day in the month grid.
    private(set) var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    private(set) var selectedDateEvents: [CalendarEvent] = []

    private let eventStore: EKEventStore

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
        authorizationState = Self.mapAuthorizationStatus(EKEventStore.authorizationStatus(for: .event))
    }

    /// Requests calendar access if not yet determined, then fetches today's events (and
    /// the currently selected day's, which default to the same day) if granted. Safe to
    /// call repeatedly — a no-op once the user has already answered.
    func requestAccessAndRefresh() async {
        if authorizationState == .notDetermined {
            let granted = (try? await eventStore.requestFullAccessToEvents()) ?? false
            authorizationState = granted ? .authorized : .denied
        }
        guard authorizationState == .authorized else { return }
        await refresh()
        await selectDate(selectedDate)
    }

    func refresh() async {
        guard authorizationState == .authorized else { return }
        todayEvents = await events(on: Calendar.current.startOfDay(for: Date()))
    }

    /// Moves the Standalone Calendar's selected day and fetches its events.
    func selectDate(_ date: Date) async {
        selectedDate = Calendar.current.startOfDay(for: date)
        guard authorizationState == .authorized else { return }
        selectedDateEvents = await events(on: selectedDate)
    }

    private func events(on day: Date) async -> [CalendarEvent] {
        guard let interval = Calendar.current.dateInterval(of: .day, for: day) else { return [] }
        let predicate = eventStore.predicateForEvents(
            withStart: interval.start, end: interval.end, calendars: nil)
        return Self.normalize(eventStore.events(matching: predicate))
    }

    private static func mapAuthorizationStatus(_ status: EKAuthorizationStatus) -> AuthorizationState {
        switch status {
        case .notDetermined: .notDetermined
        case .fullAccess: .authorized
        case .restricted, .denied, .writeOnly: .denied
        @unknown default: .denied
        }
    }

    private static func normalize(_ events: [EKEvent]) -> [CalendarEvent] {
        events
            .map {
                CalendarEvent(
                    id: $0.eventIdentifier ?? UUID().uuidString,
                    title: normalizedTitle(from: $0.title),
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    isAllDay: $0.isAllDay,
                    color: eventColor(from: $0.calendar)
                )
            }
            .sorted { $0.startDate < $1.startDate }
    }

    /// `EKCalendar.cgColor`'s component count varies with color space (grayscale is 2,
    /// most calendar colors are RGB/RGBA); guard rather than force-unwrap.
    private static func eventColor(from calendar: EKCalendar?) -> CalendarEvent.EventColor? {
        guard let components = calendar?.cgColor?.components, components.count >= 3 else {
            return nil
        }
        return CalendarEvent.EventColor(red: components[0], green: components[1], blue: components[2])
    }

    /// Pure, so it's unit-testable without constructing an `EKEvent`. `EKEvent.title` is
    /// optional and, in practice, sometimes an empty or whitespace-only string rather than
    /// nil for an untitled event — both collapse to the same fallback here.
    nonisolated static func normalizedTitle(from rawTitle: String?) -> String {
        let trimmed = (rawTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Event" : trimmed
    }

    /// Pure formatting for a single event row. `timeZone` is a parameter (not always
    /// `.current`) so tests can pin it instead of depending on the machine running them.
    nonisolated static func timeLabel(
        startDate: Date, endDate: Date, isAllDay: Bool, timeZone: TimeZone = .current
    ) -> String {
        guard !isAllDay else { return "All day" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = timeZone
        return "\(formatter.string(from: startDate)) – \(formatter.string(from: endDate))"
    }
}
