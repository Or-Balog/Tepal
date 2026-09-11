import Foundation
import Testing
@testable import TepalCore

struct ReminderPlannerTests {
    @Test func eligibleExcludesAllDayCancelledAndEndedEventsAndStablySortsTies() {
        // Break caught: filtering the wrong flags, retaining ended events, or reordering equal starts changes which meeting alerts first.
        let events = [
            CalendarEventSummary(id: "later", title: "Later", start: Date(timeIntervalSinceReferenceDate: 12_000), end: Date(timeIntervalSinceReferenceDate: 12_600), calendarID: "work", isAllDay: false, isCancelled: false),
            CalendarEventSummary(id: "tie-first", title: "Tie first", start: Date(timeIntervalSinceReferenceDate: 11_000), end: Date(timeIntervalSinceReferenceDate: 11_600), calendarID: "work", isAllDay: false, isCancelled: false),
            CalendarEventSummary(id: "all-day", title: "All day", start: Date(timeIntervalSinceReferenceDate: 10_100), end: Date(timeIntervalSinceReferenceDate: 20_000), calendarID: "work", isAllDay: true, isCancelled: false),
            CalendarEventSummary(id: "earlier", title: "Earlier", start: Date(timeIntervalSinceReferenceDate: 10_500), end: Date(timeIntervalSinceReferenceDate: 10_900), calendarID: "work", isAllDay: false, isCancelled: false),
            CalendarEventSummary(id: "tie-second", title: "Tie second", start: Date(timeIntervalSinceReferenceDate: 11_000), end: Date(timeIntervalSinceReferenceDate: 11_900), calendarID: "work", isAllDay: false, isCancelled: false),
            CalendarEventSummary(id: "cancelled", title: "Cancelled", start: Date(timeIntervalSinceReferenceDate: 10_200), end: Date(timeIntervalSinceReferenceDate: 10_800), calendarID: "work", isAllDay: false, isCancelled: true),
            CalendarEventSummary(id: "ended", title: "Ended", start: Date(timeIntervalSinceReferenceDate: 9_000), end: Date(timeIntervalSinceReferenceDate: 10_000), calendarID: "work", isAllDay: false, isCancelled: false),
        ]

        let eligible = ReminderPlanner.eligible(events, now: Date(timeIntervalSinceReferenceDate: 10_000))

        #expect(eligible.map(\.id) == ["earlier", "tie-first", "tie-second", "later"])
    }

    @Test func reminderIsDueAtTheExactLeadBoundary() {
        // Break caught: an exclusive lead-time comparison delays a reminder that is exactly ten minutes away.
        let event = CalendarEventSummary(id: "event-1", title: "Planning", start: Date(timeIntervalSinceReferenceDate: 10_600), end: Date(timeIntervalSinceReferenceDate: 11_200), calendarID: "work", isAllDay: false, isCancelled: false)

        let decision = ReminderPlanner.nextDue(events: [event], state: ReminderState(), now: Date(timeIntervalSinceReferenceDate: 10_000), lead: 600)

        #expect(decision == .show(event, ReminderOccurrenceKey(eventID: "event-1", start: Date(timeIntervalSinceReferenceDate: 10_600))))
    }

    @Test func shownOccurrenceDoesNotRepeatAfterCalendarRefresh() {
        // Break caught: refreshing equivalent event data ignores persisted occurrence deduplication and alerts twice.
        let event = CalendarEventSummary(id: "event-1", title: "Planning", start: Date(timeIntervalSinceReferenceDate: 10_600), end: Date(timeIntervalSinceReferenceDate: 11_200), calendarID: "work", isAllDay: false, isCancelled: false)
        let key = ReminderOccurrenceKey(eventID: "event-1", start: Date(timeIntervalSinceReferenceDate: 10_600))
        let state = ReminderState(shown: [key], snoozedUntil: [:], snoozeUsed: [])

        #expect(ReminderPlanner.nextDue(events: [event], state: state, now: Date(timeIntervalSinceReferenceDate: 10_001), lead: 600) == .none)
    }

    @Test func snoozeDefersTheOccurrenceForExactlyFiveMinutesThenAllowsOneMoreAlert() {
        // Break caught: snooze alerts early, never wakes, or repeats after the caller records the snoozed alert as shown.
        let event = CalendarEventSummary(id: "event-1", title: "Planning", start: Date(timeIntervalSinceReferenceDate: 11_000), end: Date(timeIntervalSinceReferenceDate: 11_600), calendarID: "work", isAllDay: false, isCancelled: false)
        let key = ReminderOccurrenceKey(eventID: "event-1", start: Date(timeIntervalSinceReferenceDate: 11_000))
        var state = ReminderState(shown: [key], snoozedUntil: [:], snoozeUsed: [])

        #expect(ReminderPlanner.snooze(key, state: &state, now: Date(timeIntervalSinceReferenceDate: 10_000), duration: 300))
        #expect(state.snoozedUntil == [key: Date(timeIntervalSinceReferenceDate: 10_300)])
        #expect(state.snoozeUsed == [key])
        #expect(!state.shown.contains(key))
        #expect(ReminderPlanner.nextDue(events: [event], state: state, now: Date(timeIntervalSinceReferenceDate: 10_299), lead: 600) == .none)
        #expect(ReminderPlanner.nextDue(events: [event], state: state, now: Date(timeIntervalSinceReferenceDate: 10_300), lead: 600) == .show(event, key))

        state.shown.insert(key)
        #expect(ReminderPlanner.nextDue(events: [event], state: state, now: Date(timeIntervalSinceReferenceDate: 10_301), lead: 600) == .none)
    }

    @Test func secondSnoozeIsRefusedWithoutChangingState() {
        // Break caught: a used occurrence can be snoozed repeatedly or a rejected attempt changes its wake time.
        let key = ReminderOccurrenceKey(eventID: "event-1", start: Date(timeIntervalSinceReferenceDate: 11_000))
        var state = ReminderState(shown: [key], snoozedUntil: [key: Date(timeIntervalSinceReferenceDate: 10_300)], snoozeUsed: [key])
        let original = state

        #expect(!ReminderPlanner.snooze(key, state: &state, now: Date(timeIntervalSinceReferenceDate: 10_050), duration: 300))
        #expect(state == original)
    }

    @Test func wakingInsideLeadWindowShowsAnUnseenFutureOccurrence() {
        // Break caught: reminder selection requires observing the lead boundary crossing and misses meetings after system sleep.
        let event = CalendarEventSummary(id: "event-1", title: "Planning", start: Date(timeIntervalSinceReferenceDate: 10_600), end: Date(timeIntervalSinceReferenceDate: 11_200), calendarID: "work", isAllDay: false, isCancelled: false)

        let decision = ReminderPlanner.nextDue(events: [event], state: ReminderState(), now: Date(timeIntervalSinceReferenceDate: 10_450), lead: 600)

        #expect(decision == .show(event, ReminderOccurrenceKey(eventID: "event-1", start: Date(timeIntervalSinceReferenceDate: 10_600))))
    }

    @Test func occurrenceAtOrAfterItsStartNeverProducesAStaleAlert() {
        // Break caught: an ongoing meeting remains eligible for a reminder after its scheduled start.
        let event = CalendarEventSummary(id: "event-1", title: "Planning", start: Date(timeIntervalSinceReferenceDate: 10_600), end: Date(timeIntervalSinceReferenceDate: 11_200), calendarID: "work", isAllDay: false, isCancelled: false)

        #expect(ReminderPlanner.nextDue(events: [event], state: ReminderState(), now: Date(timeIntervalSinceReferenceDate: 10_600), lead: 600) == .none)
        #expect(ReminderPlanner.nextDue(events: [event], state: ReminderState(), now: Date(timeIntervalSinceReferenceDate: 10_900), lead: 600) == .none)
    }

    @Test func recurringOccurrencesWithOneEventIdentifierDeduplicateByStartTime() {
        // Break caught: deduplication by event identifier alone suppresses a later occurrence in a recurring series.
        let first = CalendarEventSummary(id: "series-1", title: "Daily stand-up", start: Date(timeIntervalSinceReferenceDate: 10_300), end: Date(timeIntervalSinceReferenceDate: 10_500), calendarID: "work", isAllDay: false, isCancelled: false)
        let second = CalendarEventSummary(id: "series-1", title: "Daily stand-up", start: Date(timeIntervalSinceReferenceDate: 10_500), end: Date(timeIntervalSinceReferenceDate: 10_700), calendarID: "work", isAllDay: false, isCancelled: false)
        let state = ReminderState(
            shown: [ReminderOccurrenceKey(eventID: "series-1", start: Date(timeIntervalSinceReferenceDate: 10_300))],
            snoozedUntil: [:],
            snoozeUsed: []
        )

        let decision = ReminderPlanner.nextDue(events: [first, second], state: state, now: Date(timeIntervalSinceReferenceDate: 10_000), lead: 600)

        #expect(decision == .show(second, ReminderOccurrenceKey(eventID: "series-1", start: Date(timeIntervalSinceReferenceDate: 10_500))))
    }

    @Test func overlapUsesStrictFutureAndProposedEndBoundaries() {
        // Break caught: overlap warnings include a meeting starting now or exactly at focus end, or miss the first event strictly inside.
        let startsNow = CalendarEventSummary(id: "now", title: "Now", start: Date(timeIntervalSinceReferenceDate: 10_000), end: Date(timeIntervalSinceReferenceDate: 10_100), calendarID: "work", isAllDay: false, isCancelled: false)
        let inside = CalendarEventSummary(id: "inside", title: "Inside", start: Date(timeIntervalSinceReferenceDate: 10_300), end: Date(timeIntervalSinceReferenceDate: 10_900), calendarID: "work", isAllDay: false, isCancelled: false)
        let atEnd = CalendarEventSummary(id: "end", title: "At end", start: Date(timeIntervalSinceReferenceDate: 10_600), end: Date(timeIntervalSinceReferenceDate: 11_200), calendarID: "work", isAllDay: false, isCancelled: false)

        #expect(ReminderPlanner.overlappingEvent(events: [atEnd, startsNow, inside], now: Date(timeIntervalSinceReferenceDate: 10_000), proposedEnd: Date(timeIntervalSinceReferenceDate: 10_600)) == inside)
        #expect(ReminderPlanner.overlappingEvent(events: [atEnd, startsNow], now: Date(timeIntervalSinceReferenceDate: 10_000), proposedEnd: Date(timeIntervalSinceReferenceDate: 10_600)) == nil)
    }

    @Test func pruningRemovesOnlyStateForOccurrencesThatHaveEnded() {
        // Break caught: persisted deduplication grows forever or deletes state for a future occurrence.
        let ended = CalendarEventSummary(id: "ended", title: "Ended", start: Date(timeIntervalSinceReferenceDate: 9_000), end: Date(timeIntervalSinceReferenceDate: 10_000), calendarID: "work", isAllDay: false, isCancelled: false)
        let future = CalendarEventSummary(id: "future", title: "Future", start: Date(timeIntervalSinceReferenceDate: 11_000), end: Date(timeIntervalSinceReferenceDate: 11_600), calendarID: "work", isAllDay: false, isCancelled: false)
        let endedKey = ReminderOccurrenceKey(eventID: "ended", start: Date(timeIntervalSinceReferenceDate: 9_000))
        let futureKey = ReminderOccurrenceKey(eventID: "future", start: Date(timeIntervalSinceReferenceDate: 11_000))
        var state = ReminderState(
            shown: [endedKey, futureKey],
            snoozedUntil: [endedKey: Date(timeIntervalSinceReferenceDate: 9_500), futureKey: Date(timeIntervalSinceReferenceDate: 10_500)],
            snoozeUsed: [endedKey, futureKey]
        )

        ReminderPlanner.prune(events: [future, ended], state: &state, now: Date(timeIntervalSinceReferenceDate: 10_000))

        #expect(state.shown == [futureKey])
        #expect(state.snoozedUntil == [futureKey: Date(timeIntervalSinceReferenceDate: 10_500)])
        #expect(state.snoozeUsed == [futureKey])
    }

    @Test func pruningRemovesAStartedOccurrenceMissingFromTheCurrentQuery() {
        // Break caught: a rolling query drops an old occurrence before pruning, leaving all persisted key collections unbounded.
        let oldKey = ReminderOccurrenceKey(eventID: "old", start: Date(timeIntervalSinceReferenceDate: 9_000))
        let futureKey = ReminderOccurrenceKey(eventID: "future", start: Date(timeIntervalSinceReferenceDate: 11_000))
        var state = ReminderState(
            shown: [oldKey, futureKey],
            snoozedUntil: [oldKey: Date(timeIntervalSinceReferenceDate: 9_300), futureKey: Date(timeIntervalSinceReferenceDate: 10_500)],
            snoozeUsed: [oldKey, futureKey]
        )

        ReminderPlanner.prune(events: [], state: &state, now: Date(timeIntervalSinceReferenceDate: 10_000))

        #expect(state.shown == [futureKey])
        #expect(state.snoozedUntil == [futureKey: Date(timeIntervalSinceReferenceDate: 10_500)])
        #expect(state.snoozeUsed == [futureKey])
    }
}
