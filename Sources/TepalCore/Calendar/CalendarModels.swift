import Foundation

public enum CalendarSourceEligibility: Hashable, Sendable {
    case requiresGoogleConfirmation
    case ineligible
}

public struct CalendarDescriptor: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let sourceTitle: String
    public let sourceID: String
    public let sourceEligibility: CalendarSourceEligibility

    public init(
        id: String,
        title: String,
        sourceTitle: String,
        sourceID: String? = nil,
        sourceEligibility: CalendarSourceEligibility = .ineligible
    ) {
        self.id = id
        self.title = title
        self.sourceTitle = sourceTitle
        self.sourceID = sourceID ?? sourceTitle
        self.sourceEligibility = sourceEligibility
    }
}

public struct CalendarEventSummary: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let calendarID: String
    public let isAllDay: Bool
    public let isCancelled: Bool

    public init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        calendarID: String,
        isAllDay: Bool,
        isCancelled: Bool
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.calendarID = calendarID
        self.isAllDay = isAllDay
        self.isCancelled = isCancelled
    }
}

public struct ReminderOccurrenceKey: Hashable, Codable, Sendable {
    public let eventID: String
    public let start: Date

    public init(eventID: String, start: Date) {
        self.eventID = eventID
        self.start = start
    }
}

public struct ReminderState: Codable, Equatable, Sendable {
    public var shown: Set<ReminderOccurrenceKey>
    public var snoozedUntil: [ReminderOccurrenceKey: Date]
    public var snoozeUsed: Set<ReminderOccurrenceKey>

    public init(
        shown: Set<ReminderOccurrenceKey> = [],
        snoozedUntil: [ReminderOccurrenceKey: Date] = [:],
        snoozeUsed: Set<ReminderOccurrenceKey> = []
    ) {
        self.shown = shown
        self.snoozedUntil = snoozedUntil
        self.snoozeUsed = snoozeUsed
    }
}

public enum CalendarAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case restricted
    case denied
    case writeOnly
    case fullAccess
}

public protocol CalendarReading: Sendable {
    func authorizationStatus() async -> CalendarAuthorizationStatus
    func requestFullAccess() async throws -> Bool
    func calendars() async throws -> [CalendarDescriptor]
    func events(from: Date, through: Date, calendarIDs: Set<String>) async throws -> [CalendarEventSummary]
    func changes() -> AsyncStream<Void>
}
