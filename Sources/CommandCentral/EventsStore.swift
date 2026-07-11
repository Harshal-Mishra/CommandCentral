import EventKit
import SwiftUI

struct EventItem: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let color: Color
    let isAllDay: Bool
}

/// Reads real macOS Calendar events (next 7 days) via EventKit.
final class EventsStore: ObservableObject {
    @Published private(set) var events: [EventItem] = []
    @Published private(set) var status = EKEventStore.authorizationStatus(for: .event)

    private let store = EKEventStore()

    var isAuthorized: Bool { status == .fullAccess }

    func connect() {
        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.status = EKEventStore.authorizationStatus(for: .event)
                if granted { self.load() }
            }
        }
    }

    func loadIfAuthorized() {
        status = EKEventStore.authorizationStatus(for: .event)
        if isAuthorized { load() }
    }

    private func load() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .prefix(30)
            .map { event in
                EventItem(id: (event.eventIdentifier ?? UUID().uuidString) + "\(event.startDate.timeIntervalSince1970)",
                          title: event.title ?? "Event",
                          start: event.startDate,
                          end: event.endDate,
                          color: Color(nsColor: event.calendar?.color ?? .systemBlue),
                          isAllDay: event.isAllDay)
            }
    }
}
