import Foundation
import Testing
@testable import TepalCore

struct PomodoroEngineTests {
    private func upcomingMeeting(at start: Date) -> CalendarEventSummary {
        CalendarEventSummary(id: "meeting", title: "Design review", start: start,
            end: start.addingTimeInterval(1800), calendarID: "work", isAllDay: false, isCancelled: false)
    }

    @Test func meetingFocusEndsBeforeMeetingWithoutAutoStartingAnotherPhase() {
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        var settings = AppSettings.defaults
        settings.autoStartNextPhase = true
        var engine = PomodoroEngine(settings: settings)
        let start = engine.send(.startFocusUntilMeeting(upcomingMeeting(at: now.addingTimeInterval(900))), at: now)
        #expect(start.remaining == .seconds(780))
        #expect(start.focusDuration == 780)
        let end = engine.send(.tick, at: now.addingTimeInterval(780))
        #expect(end.phase == .idle)
        #expect(end.completedFocusCount == 1)
        #expect(end.meetingFocusEvent == nil)
        #expect(engine.send(.startFocus, at: now.addingTimeInterval(800)).remaining == .seconds(settings.focusDuration))
    }

    @Test func meetingFocusPauseRecoveryKeepsFixedDeadlineAndExcludesPausedTime() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        var engine = PomodoroEngine()
        _ = engine.send(.startFocusUntilMeeting(upcomingMeeting(at: now.addingTimeInterval(900))), at: now)
        let paused = engine.send(.pause, at: now.addingTimeInterval(60))
        let decoded = try JSONDecoder().decode(PomodoroSnapshot.self, from: JSONEncoder().encode(paused))
        var restored = try #require(PomodoroEngine(recovering: decoded))
        let resumed = restored.send(.resume, at: now.addingTimeInterval(180))
        #expect(resumed.targetEnd == now.addingTimeInterval(780))
        #expect(resumed.focusDuration == 660)
        #expect(resumed.remaining == .seconds(600))
    }

    @Test func pausedMeetingFocusExpiresWithoutClaimingACompletion() {
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        var engine = PomodoroEngine()
        _ = engine.send(.startFocusUntilMeeting(upcomingMeeting(at: now.addingTimeInterval(900))), at: now)
        _ = engine.send(.pause, at: now.addingTimeInterval(60))
        let expired = engine.send(.tick, at: now.addingTimeInterval(780))
        #expect(expired.phase == .idle)
        #expect(expired.completedFocusCount == 0)
        #expect(expired.meetingFocusEvent == nil)
    }

    @Test func meetingFocusRejectsTooShortWindowsAndSkipDoesNotCountCompletion() {
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        var engine = PomodoroEngine()
        #expect(engine.send(.startFocusUntilMeeting(upcomingMeeting(at: now.addingTimeInterval(179))), at: now).phase == .idle)
        _ = engine.send(.startFocusUntilMeeting(upcomingMeeting(at: now.addingTimeInterval(900))), at: now)
        let skipped = engine.send(.skip, at: now.addingTimeInterval(1))
        #expect(skipped.phase == .idle)
        #expect(skipped.completedFocusCount == 0)
    }

    @Test func originalDurationSurvivesPauseRecoveryAndSettingsChanges() throws {
        // Break caught: changing preferences during focus rewrites the duration eventually recorded in history.
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        var engine = PomodoroEngine()
        _ = engine.send(.startFocus, at: start)
        let paused = engine.send(.pause, at: start.addingTimeInterval(300))
        let restored = try JSONDecoder().decode(PomodoroSnapshot.self, from: JSONEncoder().encode(paused))
        var settings = AppSettings.defaults
        settings.focusDuration = 3000
        var recovered = try #require(PomodoroEngine(recovering: restored, settings: settings))
        let resumed = recovered.send(.resume, at: start.addingTimeInterval(600))
        let completed = recovered.send(.tick, at: start.addingTimeInterval(1800))
        let effects = CoordinatorPolicy.timerTransition(from: resumed, to: completed, at: start.addingTimeInterval(1800)).effects
        #expect(effects.contains(.recordCompletedFocus(start.addingTimeInterval(1800), duration: 1500)))
        let nextFocus = recovered.send(.skip, at: start.addingTimeInterval(1801))
        #expect(nextFocus.focusDuration == 3000)
    }

    @Test func defaultsExposeTheSpecifiedDurationsAndBehavior() {
        // Break caught: a default preference change silently changes the user-visible Pomodoro cadence.
        let settings = AppSettings.defaults

        #expect(settings.focusDuration == 1_500)
        #expect(settings.shortBreakDuration == 300)
        #expect(settings.longBreakDuration == 900)
        #expect(settings.longBreakEvery == 4)
        #expect(!settings.autoStartNextPhase)
        #expect(settings.reminderLead == 600)
        #expect(settings.snoozeDuration == 300)
        #expect(settings.calendarLookahead == 172_800)
        #expect(settings.calendarRefreshInterval == 900)
        #expect(!settings.soundEnabled)
        #expect(settings.ambientExcursionsEnabled)
        #expect(settings.meetingAlertsEnabled)
        #expect(settings.minimumAmbientInterval == 1_800)
    }

    @Test func startFocusCreatesA25MinuteAbsoluteDeadline() {
        // Break caught: starting focus without a 25-minute absolute deadline causes timer drift.
        var engine = PomodoroEngine()
        let snapshot = engine.send(.startFocus, at: Date(timeIntervalSinceReferenceDate: 10_000))

        #expect(snapshot.phase == .focus)
        #expect(snapshot.remaining == .seconds(1_500))
        #expect(snapshot.targetEnd == Date(timeIntervalSinceReferenceDate: 11_500))
        #expect(snapshot.completedFocusCount == 0)
        #expect(!snapshot.isPaused)
    }

    @Test func tickDerivesRemainingFromTheOriginalDeadline() {
        // Break caught: decrementing a counter instead of measuring from the target deadline reports stale time.
        var engine = PomodoroEngine()
        _ = engine.send(.startFocus, at: Date(timeIntervalSinceReferenceDate: 10_000))
        let snapshot = engine.send(.tick, at: Date(timeIntervalSinceReferenceDate: 10_037))

        #expect(snapshot.remaining == .seconds(1_463))
        #expect(snapshot.targetEnd == Date(timeIntervalSinceReferenceDate: 11_500))
    }

    @Test func pauseFreezesTheRemainingDuration() {
        // Break caught: pause retaining a target end lets elapsed wall time consume a paused session.
        var engine = PomodoroEngine()
        _ = engine.send(.startFocus, at: Date(timeIntervalSinceReferenceDate: 10_000))
        let paused = engine.send(.pause, at: Date(timeIntervalSinceReferenceDate: 10_120))
        let later = engine.send(.tick, at: Date(timeIntervalSinceReferenceDate: 20_000))

        #expect(paused.remaining == .seconds(1_380))
        #expect(paused.targetEnd == nil)
        #expect(paused.isPaused)
        #expect(later.remaining == .seconds(1_380))
        #expect(later.targetEnd == nil)
        #expect(later.isPaused)
    }

    @Test func pauseAtTheExactDeadlineSettlesFocusWithoutPausingTheNewBreak() {
        // Break caught: a stale Pause at the focus deadline erases the completion or pauses the newly auto-started break.
        var settings = AppSettings.defaults
        settings.focusDuration = 60
        settings.autoStartNextPhase = true
        var engine = PomodoroEngine(settings: settings)
        let start = Date(timeIntervalSinceReferenceDate: 10_000)
        _ = engine.send(.startFocus, at: start)

        let snapshot = engine.send(.pause, at: start.addingTimeInterval(60))

        #expect(snapshot.phase == .shortBreak)
        #expect(snapshot.completedFocusCount == 1)
        #expect(!snapshot.isPaused)
        #expect(snapshot.targetEnd == start.addingTimeInterval(360))
    }

    @Test func pauseAfterTheDeadlineSettlesFocusWithoutPausingTheNewBreak() {
        // Break caught: a delayed stale Pause consumes the newly auto-started break after settling the earned focus.
        var settings = AppSettings.defaults
        settings.focusDuration = 60
        settings.autoStartNextPhase = true
        var engine = PomodoroEngine(settings: settings)
        let start = Date(timeIntervalSinceReferenceDate: 20_000)
        _ = engine.send(.startFocus, at: start)

        let observation = start.addingTimeInterval(65)
        let snapshot = engine.send(.pause, at: observation)

        #expect(snapshot.phase == .shortBreak)
        #expect(snapshot.completedFocusCount == 1)
        #expect(!snapshot.isPaused)
        #expect(snapshot.targetEnd == observation.addingTimeInterval(300))
    }

    @Test func resumeUsesTheFrozenDurationToCreateANewDeadline() {
        // Break caught: resume rebuilding a deadline from the original start loses the paused duration.
        var engine = PomodoroEngine()
        _ = engine.send(.startFocus, at: Date(timeIntervalSinceReferenceDate: 10_000))
        _ = engine.send(.pause, at: Date(timeIntervalSinceReferenceDate: 10_120))
        let resumed = engine.send(.resume, at: Date(timeIntervalSinceReferenceDate: 20_000))

        #expect(resumed.remaining == .seconds(1_380))
        #expect(resumed.targetEnd == Date(timeIntervalSinceReferenceDate: 21_380))
        #expect(!resumed.isPaused)
    }

    @Test func completedFocusMovesToAPausedShortBreak() {
        // Break caught: a completed focus either fails to advance or automatically starts the next phase.
        var engine = PomodoroEngine()
        _ = engine.send(.startFocus, at: Date(timeIntervalSinceReferenceDate: 10_000))
        let snapshot = engine.send(.tick, at: Date(timeIntervalSinceReferenceDate: 11_500))

        #expect(snapshot.phase == .shortBreak)
        #expect(snapshot.remaining == .seconds(300))
        #expect(snapshot.targetEnd == nil)
        #expect(snapshot.completedFocusCount == 1)
        #expect(snapshot.isPaused)
    }

    @Test func autoStartSettingCreatesADeadlineForTheNextPhase() {
        // Break caught: enabling auto-start still leaves the completed focus phase paused.
        var settings = AppSettings.defaults
        settings.autoStartNextPhase = true
        var engine = PomodoroEngine(settings: settings)
        _ = engine.send(.startFocus, at: Date(timeIntervalSinceReferenceDate: 10_000))
        let snapshot = engine.send(.tick, at: Date(timeIntervalSinceReferenceDate: 11_500))

        #expect(snapshot.phase == .shortBreak)
        #expect(snapshot.remaining == .seconds(300))
        #expect(snapshot.targetEnd == Date(timeIntervalSinceReferenceDate: 11_800))
        #expect(!snapshot.isPaused)
    }

    @Test func directSettingsAreNormalizedByTheFreshEngineInitializer() {
        // Break caught: a direct caller bypasses SettingsStore and starts a zero-length timer with no long-break cadence.
        var invalid = AppSettings.defaults
        invalid.focusDuration = 0
        invalid.longBreakEvery = 0
        var engine = PomodoroEngine(settings: invalid)

        let started = engine.send(.startFocus, at: Date(timeIntervalSinceReferenceDate: 10_000))
        let completed = engine.send(.tick, at: Date(timeIntervalSinceReferenceDate: 10_060))

        #expect(engine.settings.focusDuration == 60)
        #expect(engine.settings.longBreakEvery == 1)
        #expect(started.remaining == .seconds(60))
        #expect(started.targetEnd == Date(timeIntervalSinceReferenceDate: 10_060))
        #expect(completed.phase == .longBreak)
    }

    @Test func directSettingsAreNormalizedByTheRecoveryInitializer() throws {
        // Break caught: recovered engines retain invalid direct settings even though fresh engines normalize them.
        var invalid = AppSettings.defaults
        invalid.longBreakDuration = 0
        invalid.longBreakEvery = 0
        let recovered = PomodoroSnapshot(
            phase: .focus,
            remaining: .seconds(1),
            targetEnd: Date(timeIntervalSinceReferenceDate: 20_001),
            completedFocusCount: 0,
            isPaused: false
        )
        var engine = try #require(PomodoroEngine(recovering: recovered, settings: invalid))

        let completed = engine.send(.tick, at: Date(timeIntervalSinceReferenceDate: 20_001))

        #expect(engine.settings.longBreakDuration == 60)
        #expect(engine.settings.longBreakEvery == 1)
        #expect(completed.phase == .longBreak)
        #expect(completed.remaining == .seconds(60))
    }

    @Test func fourthCompletedFocusMovesToAPausedLongBreak() {
        // Break caught: the long-break cadence chooses a short break after the fourth completed focus.
        let recovered = PomodoroSnapshot(
            phase: .focus,
            remaining: .seconds(1),
            targetEnd: Date(timeIntervalSinceReferenceDate: 11_500),
            completedFocusCount: 3,
            isPaused: false
        )
        var engine = PomodoroEngine(recovering: recovered)!
        let snapshot = engine.send(.tick, at: Date(timeIntervalSinceReferenceDate: 11_500))

        #expect(snapshot.phase == .longBreak)
        #expect(snapshot.remaining == .seconds(900))
        #expect(snapshot.targetEnd == nil)
        #expect(snapshot.completedFocusCount == 4)
        #expect(snapshot.isPaused)
    }

    @Test func skipMovesFocusToAnUnstartedShortBreakWithoutCountingIt() {
        // Break caught: skip incorrectly records an incomplete focus as completed.
        var engine = PomodoroEngine()
        _ = engine.send(.startFocus, at: Date(timeIntervalSinceReferenceDate: 10_000))
        let snapshot = engine.send(.skip, at: Date(timeIntervalSinceReferenceDate: 10_010))

        #expect(snapshot.phase == .shortBreak)
        #expect(snapshot.remaining == .seconds(300))
        #expect(snapshot.completedFocusCount == 0)
        #expect(snapshot.isPaused)
    }

    @Test func skipAtTheExactDeadlineSettlesFocusWithoutSkippingTheEarnedBreak() {
        // Break caught: a stale Skip at the focus deadline treats the expired focus as abandoned or immediately skips its break.
        var settings = AppSettings.defaults
        settings.focusDuration = 60
        var engine = PomodoroEngine(settings: settings)
        let start = Date(timeIntervalSinceReferenceDate: 30_000)
        _ = engine.send(.startFocus, at: start)

        let snapshot = engine.send(.skip, at: start.addingTimeInterval(60))

        #expect(snapshot.phase == .shortBreak)
        #expect(snapshot.completedFocusCount == 1)
        #expect(snapshot.isPaused)
    }

    @Test func skipAfterTheDeadlineSettlesFocusWithoutSkippingTheEarnedBreak() {
        // Break caught: a delayed stale Skip advances twice and loses the break earned by the completed focus.
        var settings = AppSettings.defaults
        settings.focusDuration = 60
        var engine = PomodoroEngine(settings: settings)
        let start = Date(timeIntervalSinceReferenceDate: 40_000)
        _ = engine.send(.startFocus, at: start)

        let snapshot = engine.send(.skip, at: start.addingTimeInterval(65))

        #expect(snapshot.phase == .shortBreak)
        #expect(snapshot.completedFocusCount == 1)
        #expect(snapshot.isPaused)
    }

    @Test func resetAfterAnUnobservedDeadlineStillReturnsTheEngineToIdle() {
        // Break caught: a Reset arriving after an expired, not-yet-ticked deadline
        // only settles the phase and leaves the timer running.
        var settings = AppSettings.defaults
        settings.autoStartNextPhase = true
        var engine = PomodoroEngine(settings: settings)
        let start = Date(timeIntervalSinceReferenceDate: 50_000)
        _ = engine.send(.startFocus, at: start)

        let snapshot = engine.send(.reset, at: start.addingTimeInterval(settings.focusDuration + 5))

        #expect(snapshot.phase == .idle)
        #expect(snapshot.targetEnd == nil)
        #expect(snapshot.completedFocusCount == 0)
        #expect(!snapshot.isPaused)
    }

    @Test func resetAfterAMeetingFocusDeadlineClearsTheCompletedCount() {
        // Break caught: a Reset at the meeting handover is swallowed by the handover.
        let now = Date(timeIntervalSinceReferenceDate: 70_000)
        var engine = PomodoroEngine()
        _ = engine.send(.startFocusUntilMeeting(upcomingMeeting(at: now.addingTimeInterval(900))), at: now)

        let snapshot = engine.send(.reset, at: now.addingTimeInterval(790))

        #expect(snapshot.phase == .idle)
        #expect(snapshot.completedFocusCount == 0)
        #expect(snapshot.meetingFocusEvent == nil)
    }

    @Test func resetReturnsTheEngineToIdle() {
        // Break caught: reset retains an active deadline or previously completed focus count.
        var engine = PomodoroEngine()
        _ = engine.send(.startFocus, at: Date(timeIntervalSinceReferenceDate: 10_000))
        _ = engine.send(.tick, at: Date(timeIntervalSinceReferenceDate: 11_500))
        let snapshot = engine.send(.reset, at: Date(timeIntervalSinceReferenceDate: 12_000))

        #expect(snapshot.phase == .idle)
        #expect(snapshot.remaining == .zero)
        #expect(snapshot.targetEnd == nil)
        #expect(snapshot.completedFocusCount == 0)
        #expect(!snapshot.isPaused)
    }

    @Test func delayedTickAfterOneHourCompletesOnlyTheCurrentFocusPhase() {
        // Break caught: wake recovery replays every missed phase instead of advancing once.
        var engine = PomodoroEngine()
        _ = engine.send(.startFocus, at: Date(timeIntervalSinceReferenceDate: 10_000))
        let snapshot = engine.send(.tick, at: Date(timeIntervalSinceReferenceDate: 13_600))

        #expect(snapshot.phase == .shortBreak)
        #expect(snapshot.remaining == .seconds(300))
        #expect(snapshot.completedFocusCount == 1)
        #expect(snapshot.targetEnd == nil)
        #expect(snapshot.isPaused)
    }

    @Test func recoversAValidPausedSnapshot() {
        // Break caught: valid persisted paused state is discarded during app relaunch.
        let persisted = PomodoroSnapshot(
            phase: .shortBreak,
            remaining: .seconds(240),
            targetEnd: nil,
            completedFocusCount: 2,
            isPaused: true
        )
        var engine = PomodoroEngine(recovering: persisted)!
        let snapshot = engine.send(.tick, at: Date(timeIntervalSinceReferenceDate: 99_999))

        #expect(snapshot == persisted)
    }

    @Test func rejectsRecoveryWithANegativeRemainingDuration() {
        // Break caught: corrupted negative persisted time produces an invalid live timer.
        let invalid = PomodoroSnapshot(
            phase: .focus,
            remaining: .seconds(-1),
            targetEnd: Date(timeIntervalSinceReferenceDate: 11_500),
            completedFocusCount: 0,
            isPaused: false
        )

        #expect(PomodoroEngine(recovering: invalid) == nil)
    }

    @Test func rejectsRecoveryWithInconsistentRunningState() {
        // Break caught: a running persisted phase without a deadline cannot recompute remaining time.
        let invalid = PomodoroSnapshot(
            phase: .focus,
            remaining: .seconds(240),
            targetEnd: nil,
            completedFocusCount: 0,
            isPaused: false
        )

        #expect(PomodoroEngine(recovering: invalid) == nil)
    }
}
