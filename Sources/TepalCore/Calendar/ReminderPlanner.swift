import Foundation

public enum ReminderDecision: Equatable, Sendable {
    case none
    case show(CalendarEventSummary, ReminderOccurrenceKey)
}

public struct ReminderPlanner: Sendable {
    public static func eligible(_ events: [CalendarEventSummary], now: Date) -> [CalendarEventSummary] {
        events.enumerated()
            .filter { _, event in
                !event.isAllDay && !event.isCancelled && event.end > now
            }
            .sorted { left, right in
                if left.element.start == right.element.start {
                    return left.offset < right.offset
                }
                return left.element.start < right.element.start
            }
            .map(\.element)
    }

    public static func nextDue(
        events: [CalendarEventSummary],
        state: ReminderState,
        now: Date,
        lead: TimeInterval
    ) -> ReminderDecision {
        for event in eligible(events, now: now) where event.start > now {
            let key = ReminderOccurrenceKey(eventID: event.id, start: event.start)

            if state.shown.contains(key) {
                continue
            }

            if let snoozedUntil = state.snoozedUntil[key] {
                if now >= snoozedUntil {
                    return .show(event, key)
                }
                continue
            }

            if event.start.timeIntervalSince(now) <= lead {
                return .show(event, key)
            }
        }

        return .none
    }

    @discardableResult
    public static func snooze(
        _ key: ReminderOccurrenceKey,
        state: inout ReminderState,
        now: Date,
        duration: TimeInterval
    ) -> Bool {
        guard !state.snoozeUsed.contains(key) else {
            return false
        }

        state.shown.subtract([key])
        state.snoozedUntil[key] = now.addingTimeInterval(duration)
        state.snoozeUsed.insert(key)
        return true
    }

    public static func overlappingEvent(
        events: [CalendarEventSummary],
        now: Date,
        proposedEnd: Date
    ) -> CalendarEventSummary? {
        eligible(events, now: now).first { event in
            event.start < proposedEnd && event.start > now
        }
    }

    public static func prune(
        events _: [CalendarEventSummary],
        state: inout ReminderState,
        now: Date
    ) {
        let trackedKeys = state.shown
            .union(state.snoozeUsed)
            .union(Set(state.snoozedUntil.keys))
        let staleKeys = Set(trackedKeys.filter { $0.start <= now })

        state.shown.subtract(staleKeys)
        state.snoozedUntil = state.snoozedUntil.filter { !staleKeys.contains($0.key) }
        state.snoozeUsed.subtract(staleKeys)
    }
}
