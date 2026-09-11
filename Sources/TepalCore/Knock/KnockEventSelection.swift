import Foundation

public enum KnockEventSelection {
    public static func next(in events: [CalendarEventSummary], after now: Date, calendarIDs: Set<String>) -> CalendarEventSummary? {
        events.filter { !$0.isCancelled && !$0.isAllDay && $0.start > now && calendarIDs.contains($0.calendarID) }
            .min { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }
}
