import TepalCore
import EventKit
import Foundation

protocol EventKitEventInput {
    var eventIdentifier: String! { get }
    var calendarItemIdentifier: String { get }
    var title: String! { get }
    var startDate: Date! { get }
    var endDate: Date! { get }
    var calendarIdentifier: String { get }
    var isAllDay: Bool { get }
    var status: EKEventStatus { get }
}

extension EKEvent: EventKitEventInput {
    var calendarIdentifier: String {
        calendar.calendarIdentifier
    }
}

enum EventKitEventMapper {
    static func summary<Event: EventKitEventInput>(from event: Event) -> CalendarEventSummary? {
        guard let start = event.startDate, let end = event.endDate else {
            return nil
        }

        return CalendarEventSummary(
            id: event.eventIdentifier ?? event.calendarItemIdentifier,
            title: event.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled event",
            start: start,
            end: end,
            calendarID: event.calendarIdentifier,
            isAllDay: event.isAllDay,
            isCancelled: event.status == .canceled
        )
    }
}

enum EventKitSourceClassifier {
    static func eligibility(
        sourceType: EKSourceType,
        title: String,
        identifier: String
    ) -> CalendarSourceEligibility {
        _ = title
        _ = identifier
        return sourceType == .calDAV ? .requiresGoogleConfirmation : .ineligible
    }
}

public actor EventKitCalendarReader: CalendarReading {
    private let store: EKEventStore

    public init() {
        store = EKEventStore()
    }

    public func authorizationStatus() async -> CalendarAuthorizationStatus {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            .notDetermined
        case .restricted:
            .restricted
        case .denied:
            .denied
        case .writeOnly:
            .writeOnly
        case .fullAccess:
            .fullAccess
        @unknown default:
            .denied
        }
    }

    public func requestFullAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    public func calendars() async throws -> [CalendarDescriptor] {
        store.calendars(for: .event).map { calendar in
            CalendarDescriptor(
                id: calendar.calendarIdentifier,
                title: calendar.title,
                sourceTitle: calendar.source.title,
                sourceID: calendar.source.sourceIdentifier,
                sourceEligibility: EventKitSourceClassifier.eligibility(
                    sourceType: calendar.source.sourceType,
                    title: calendar.source.title,
                    identifier: calendar.source.sourceIdentifier
                )
            )
        }
    }

    public func events(
        from: Date,
        through: Date,
        calendarIDs: Set<String>
    ) async throws -> [CalendarEventSummary] {
        guard from <= through, !calendarIDs.isEmpty else {
            return []
        }

        let selectedCalendars = store.calendars(for: .event).filter {
            calendarIDs.contains($0.calendarIdentifier)
        }
        guard !selectedCalendars.isEmpty else {
            return []
        }

        let predicate = store.predicateForEvents(
            withStart: from,
            end: through,
            calendars: selectedCalendars
        )
        return store.events(matching: predicate).compactMap(EventKitEventMapper.summary)
    }

    public nonisolated func changes() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let observation = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged,
                object: nil,
                queue: nil
            ) { _ in
                continuation.yield()
            }
            let token = NotificationToken(observation)
            continuation.onTermination = { _ in
                NotificationCenter.default.removeObserver(token.value)
            }
        }
    }
}

private final class NotificationToken: @unchecked Sendable {
    let value: NSObjectProtocol

    init(_ value: NSObjectProtocol) {
        self.value = value
    }
}
