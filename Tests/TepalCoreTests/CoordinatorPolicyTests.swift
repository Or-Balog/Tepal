import Foundation
import Testing
@testable import TepalCore

struct CoordinatorPolicyTests {
    @Test func meetingReminderEndsAmbientExcursionBeforeStartingMeetingAlert() {
        // Break caught: a meeting leaves an ambient excursion active underneath it and restores that stale panel afterward.
        let event = meeting(id: "planning", start: 10_600)
        let key = ReminderOccurrenceKey(eventID: event.id, start: event.start)

        let result = CoordinatorPolicy.reminder(.show(event, key))

        #expect(result.petEvents == [.excursionEnded, .meetingStarted])
        #expect(result.effects == [.showMeeting(event, key), .persist])
    }

    @Test func completedFocusProducesOneHistoryRecordOnlyOnTheCountTransition() {
        // Break caught: ordinary countdown ticks or repeated evaluation of the completed snapshot duplicate focus history.
        let completion = Date(timeIntervalSinceReferenceDate: 10_000)
        let before = PomodoroSnapshot(
            phase: .focus,
            remaining: .seconds(1),
            targetEnd: completion,
            completedFocusCount: 0,
            isPaused: false
        )
        let after = PomodoroSnapshot(
            phase: .shortBreak,
            remaining: .seconds(300),
            targetEnd: nil,
            completedFocusCount: 1,
            isPaused: true
        )

        let transition = CoordinatorPolicy.timerTransition(from: before, to: after, at: completion)
        let repeated = CoordinatorPolicy.timerTransition(from: after, to: after, at: completion)

        #expect(transition.petEvents == [.timerPhase(.shortBreak)])
        #expect(transition.effects == [.recordCompletedFocus(completion), .persist])
        #expect(repeated.petEvents.isEmpty)
        #expect(repeated.effects.isEmpty)
    }

    @Test func delayedWakeRecordsTheScheduledFocusEndInsteadOfTheWakeTime() {
        // Break caught: sleep/wake delay changes the historical completion timestamp to the later observation time.
        let scheduledEnd = Date(timeIntervalSinceReferenceDate: 20_000)
        let wake = scheduledEnd.addingTimeInterval(600)
        let before = PomodoroSnapshot(
            phase: .focus,
            remaining: .zero,
            targetEnd: scheduledEnd,
            completedFocusCount: 2,
            isPaused: false
        )
        let after = PomodoroSnapshot(
            phase: .shortBreak,
            remaining: .seconds(300),
            targetEnd: nil,
            completedFocusCount: 3,
            isPaused: true
        )

        let transition = CoordinatorPolicy.timerTransition(from: before, to: after, at: wake)

        #expect(transition.effects.contains(.recordCompletedFocus(scheduledEnd)))
        #expect(!transition.effects.contains(.recordCompletedFocus(wake)))
    }

    @Test func calendarFailureDoesNotEmitAPetFailureOrTimerEffect() {
        // Break caught: a recoverable EventKit error changes or persists unrelated Pomodoro and pet state.
        let result = CoordinatorPolicy.calendarFailure()

        #expect(result.petEvents.isEmpty)
        #expect(result.effects.isEmpty)
    }

    @Test func focusOverlapProducesAWarningWithoutStartingOrChangingTheTimer() {
        // Break caught: overlap handling starts, shortens, or otherwise mutates the timer before the user confirms.
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let inside = meeting(id: "stand-up", start: 10_300)

        let result = CoordinatorPolicy.focusRequest(
            events: [inside],
            now: now,
            focusDuration: 1_500
        )

        #expect(result.petEvents.isEmpty)
        #expect(result.effects == [.showFocusOverlap(inside)])
    }

    private func meeting(id: String, start: TimeInterval) -> CalendarEventSummary {
        CalendarEventSummary(
            id: id,
            title: "Planning",
            start: Date(timeIntervalSinceReferenceDate: start),
            end: Date(timeIntervalSinceReferenceDate: start + 600),
            calendarID: "work",
            isAllDay: false,
            isCancelled: false
        )
    }
}
