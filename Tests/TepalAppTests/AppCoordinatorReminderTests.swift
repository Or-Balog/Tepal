import AppKit
import TepalCore
import Foundation
import ServiceManagement
import SwiftData
import Testing
@testable import TepalApp
@testable import TepalMac

@MainActor
struct AppCoordinatorReminderTests {
    @Test func meetingFocusUsesCalendarWindowAndPresentsPreparation() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        let clock = MutableTestClock(now)
        let event = meeting(id: "design-review", start: now.addingTimeInterval(900))
        let fixture = makeFixture(clock: clock, calendar: TestCalendar(events: [event]), sleepRecorder: SleepRecorder()) { settings in
            settings.meetingAlertsEnabled = false
        }
        let excursion = PersistenceInspectingExcursion()
        let coordinator = fixture.makeCoordinator(excursionController: excursion)
        defer { fixture.cleanUp(coordinator) }
        coordinator.start()
        try await eventually { coordinator.meetingFocusCandidate != nil }
        coordinator.startFocusUntilNextMeeting()
        #expect(coordinator.pomodoro.focusDuration == 780)
        #expect(coordinator.focusOverlap == nil)
        clock.advance(by: 780)
        coordinator.pauseOrResume()
        #expect(coordinator.pomodoro.phase == .idle)
        #expect(excursion.presentedTitles == [event.title])
        #expect(excursion.presentationCount == 1)
        coordinator.pauseOrResume()
        #expect(excursion.presentationCount == 1)
    }

    @Test func habitatAnimationTriggerChangesWhenReducedMotionBecomesEffective() {
        // Break caught: Reduced Motion changes at a stable pose do not create a transaction that can snap habitat fades.
        let moving = TepalVisualState(
            pose: .completionBloom,
            timerProgress: 1,
            palette: .moonFern,
            growth: TepalGrowthProfile(completedFocuses: 4),
            reducedMotion: false
        )
        let reduced = TepalVisualState(
            pose: .completionBloom,
            timerProgress: 1,
            palette: .moonFern,
            growth: TepalGrowthProfile(completedFocuses: 4),
            reducedMotion: true
        )

        #expect(TepalHabitatAnimationTrigger(state: moving)
            != TepalHabitatAnimationTrigger(state: reduced))
    }

    @Test func historyCountLoadsAtInitialization() {
        // Break caught: Tepal growth starts from timer-session recovery instead of durable history.
        let history: any FocusHistoryRecording = FakeHistoryRecorder(completedFocuses: 12)
        let fixture = makeFixture(
            clock: MutableTestClock(Date(timeIntervalSinceReferenceDate: 1_000)),
            calendar: TestCalendar(events: []),
            sleepRecorder: SleepRecorder()
        ) { _ in }
        let coordinator = fixture.makeCoordinator(historyRecorder: history)
        defer { fixture.cleanUp(coordinator) }

        #expect(coordinator.tepalCompletedFocusCount == 12)
        #expect(coordinator.tepalVisualState.growth.tier == .flourishing)
    }

    @Test(arguments: [
        (CosmeticReward.glow, 1, TepalGrowthTier.glowing),
        (.sparkle, 4, .sprouted),
        (.colorShift, 12, .flourishing),
        (.morph, 25, .mature),
    ])
    func persistedRewardIdentifiersRestoreEveryTepalMilestone(
        reward: CosmeticReward,
        expectedCount: Int,
        expectedTier: TepalGrowthTier
    ) {
        // Break caught: a compatible persisted reward identifier is discarded when rebuilding Tepal growth.
        let history = FakeHistoryRecorder(
            completedFocuses: 0,
            existingRewardIDs: [reward]
        )
        let fixture = makeFixture(
            clock: MutableTestClock(Date(timeIntervalSinceReferenceDate: 1_050)),
            calendar: TestCalendar(events: []),
            sleepRecorder: SleepRecorder()
        ) { _ in }
        let coordinator = fixture.makeCoordinator(historyRecorder: history)
        defer { fixture.cleanUp(coordinator) }

        #expect(coordinator.tepalCompletedFocusCount == expectedCount)
        #expect(coordinator.tepalVisualState.growth.tier == expectedTier)
    }

    @Test func legacyRewardMilestoneWinsWhenItsSessionCountIsInconsistent() {
        // Break caught: a partially migrated store resets a mature persisted reward to the lower raw session count.
        let history = FakeHistoryRecorder(
            completedFocuses: 2,
            existingRewardIDs: [.morph]
        )
        let fixture = makeFixture(
            clock: MutableTestClock(Date(timeIntervalSinceReferenceDate: 1_075)),
            calendar: TestCalendar(events: []),
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.tepalPalette = .frostBloom
        }
        let coordinator = fixture.makeCoordinator(historyRecorder: history)
        defer { fixture.cleanUp(coordinator) }

        #expect(coordinator.tepalCompletedFocusCount == 25)
        #expect(coordinator.tepalVisualState.growth.tier == .mature)
        #expect(coordinator.tepalVisualState.palette == .frostBloom)
    }

    @Test func lockedPaletteCannotBeSelectedButAvailablePalettePersists() {
        // Break caught: palette selection equips an unearned choice or fails to persist an accepted starter palette.
        let fixture = makeFixture(
            clock: MutableTestClock(Date(timeIntervalSinceReferenceDate: 1_100)),
            calendar: TestCalendar(events: []),
            sleepRecorder: SleepRecorder()
        ) { _ in }
        let history = FakeHistoryRecorder(completedFocuses: 0)
        let coordinator = fixture.makeCoordinator(historyRecorder: history)
        defer { fixture.cleanUp(coordinator) }

        coordinator.selectTepalPalette(.frostBloom)
        #expect(coordinator.settings.tepalPalette == .moonFern)
        coordinator.selectTepalPalette(.dewdrop)

        #expect(coordinator.settings.tepalPalette == .dewdrop)
        #expect(fixture.reloadedStore().settings.tepalPalette == .dewdrop)
    }

    @Test func unavailableHistoryRendersSeedlingFallbackWithoutDeletingSavedEarnedPalette() {
        // Break caught: missing history either presents unverified earned growth or destroys the user's saved palette preference.
        let fixture = makeFixture(
            clock: MutableTestClock(Date(timeIntervalSinceReferenceDate: 1_200)),
            calendar: TestCalendar(events: []),
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.tepalPalette = .pollenGold
        }
        let coordinator = fixture.makeCoordinator(historyRecorder: nil)
        defer { fixture.cleanUp(coordinator) }

        #expect(coordinator.tepalCompletedFocusCount == 0)
        #expect(coordinator.tepalVisualState.growth.tier == .seedling)
        #expect(coordinator.tepalVisualState.palette == .moonFern)
        #expect(coordinator.settings.tepalPalette == .pollenGold)
        #expect(fixture.reloadedStore().settings.tepalPalette == .pollenGold)
    }

    @Test func successfulFourthCompletionQueuesPollenGoldUntilBloomFinishes() async throws {
        // Break caught: the palette banner competes with the signature completion bloom instead of following it.
        let now = Date(timeIntervalSinceReferenceDate: 1_300)
        let clock = MutableTestClock(now)
        let history = FakeHistoryRecorder(completedFocuses: 3, rewardsOnRecord: [])
        let fixture = makeFixture(
            clock: clock,
            calendar: TestCalendar(events: []),
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 60
        }
        let coordinator = fixture.makeCoordinator(historyRecorder: history)
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        coordinator.startFocus()
        clock.advance(by: 60)
        coordinator.pauseOrResume()

        #expect(history.operations.suffix(2) == ["record", "snapshot"])
        #expect(coordinator.tepalCompletedFocusCount == 4)
        #expect(coordinator.pendingTepalUnlock == nil)
        #expect(coordinator.tepalVisualState.palette == .moonFern)
        #expect(coordinator.tepalVisualState.pose == .completionBloom)

        clock.advance(by: 2)
        fixture.postWake()
        try await eventually {
            coordinator.tepalVisualState.pose == .resting
                && coordinator.pendingTepalUnlock == .pollenGold
        }
    }

    @Test func persistedCompletionBloomsEvenWhenNoPaletteUnlocks() {
        // Break caught: the signature completion bloom is incorrectly gated on a newly returned cosmetic reward.
        let now = Date(timeIntervalSinceReferenceDate: 1_400)
        let clock = MutableTestClock(now)
        let history = FakeHistoryRecorder(completedFocuses: 1, rewardsOnRecord: [])
        let fixture = makeFixture(
            clock: clock,
            calendar: TestCalendar(events: []),
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 60
        }
        let coordinator = fixture.makeCoordinator(historyRecorder: history)
        defer { fixture.cleanUp(coordinator) }

        coordinator.startFocus()
        clock.advance(by: 60)
        coordinator.pauseOrResume()

        #expect(history.recordCount == 1)
        #expect(coordinator.tepalCompletedFocusCount == 2)
        #expect(coordinator.pendingTepalUnlock == nil)
        #expect(coordinator.tepalVisualState.pose == .completionBloom)
    }

    @Test func unavailableHistoryAllowsOneBoundedCompletionBloomWithoutGrowthOrUnlock() async throws {
        // Break caught: history failure suppresses completion feedback or invents durable growth and an earned unlock.
        let now = Date(timeIntervalSinceReferenceDate: 1_500)
        let clock = MutableTestClock(now)
        let fixture = makeFixture(
            clock: clock,
            calendar: TestCalendar(events: []),
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 60
        }
        let coordinator = fixture.makeCoordinator(historyRecorder: nil)
        defer { fixture.cleanUp(coordinator) }
        coordinator.start()
        coordinator.startFocus()
        clock.advance(by: 60)

        coordinator.pauseOrResume()

        #expect(coordinator.tepalVisualState.pose == .completionBloom)
        #expect(coordinator.tepalCompletedFocusCount == 0)
        #expect(coordinator.pendingTepalUnlock == nil)

        clock.advance(by: 2)
        fixture.postWake()
        try await eventually { coordinator.tepalVisualState.pose == .resting }
        fixture.postWake()
        await settle()
        #expect(coordinator.tepalVisualState.pose == .resting)
    }

    @Test func throwingHistoryRecordPreservesEarnedGrowthButKeepsOneBoundedBloom() async throws {
        // Break caught: a temporary write failure erases the last verified growth.
        let now = Date(timeIntervalSinceReferenceDate: 1_510)
        let clock = MutableTestClock(now)
        let history = FakeHistoryRecorder(completedFocuses: 12, rewardsOnRecord: [])
        let fixture = makeFixture(
            clock: clock,
            calendar: TestCalendar(events: []),
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 60
            settings.tepalPalette = .emberMoss
        }
        let coordinator = fixture.makeCoordinator(historyRecorder: history)
        defer { fixture.cleanUp(coordinator) }
        #expect(coordinator.tepalVisualState.palette == .emberMoss)
        history.failFutureRecords()
        coordinator.start()
        coordinator.startFocus()
        clock.advance(by: 60)

        coordinator.pauseOrResume()

        #expect(coordinator.tepalCompletedFocusCount == 12)
        #expect(coordinator.historySaveError != nil)
        #expect(coordinator.pendingTepalUnlock == nil)
        #expect(coordinator.settings.tepalPalette == .emberMoss)
        #expect(fixture.reloadedStore().settings.tepalPalette == .emberMoss)
        #expect(coordinator.tepalVisualState.growth.tier == .flourishing)
        #expect(coordinator.tepalVisualState.palette == .emberMoss)
        #expect(coordinator.tepalVisualState.pose == .completionBloom)

        clock.advance(by: 2)
        fixture.postWake()
        try await eventually { coordinator.tepalVisualState.pose == .resting }
        fixture.postWake()
        await settle()
        #expect(coordinator.tepalVisualState.pose == .resting)
    }

    @Test func throwingPostRecordHistorySnapshotPreservesEarnedGrowthButKeepsOneBoundedBloom() async throws {
        // Break caught: a failed read after saving makes previously earned growth disappear.
        let now = Date(timeIntervalSinceReferenceDate: 1_520)
        let clock = MutableTestClock(now)
        let history = FakeHistoryRecorder(completedFocuses: 12, rewardsOnRecord: [])
        let fixture = makeFixture(
            clock: clock,
            calendar: TestCalendar(events: []),
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 60
            settings.tepalPalette = .emberMoss
        }
        let coordinator = fixture.makeCoordinator(historyRecorder: history)
        defer { fixture.cleanUp(coordinator) }
        #expect(coordinator.tepalVisualState.palette == .emberMoss)
        history.failFutureSnapshotReads()
        coordinator.start()
        coordinator.startFocus()
        clock.advance(by: 60)

        coordinator.pauseOrResume()

        #expect(history.recordCount == 1)
        #expect(coordinator.tepalCompletedFocusCount == 12)
        #expect(coordinator.historySaveError != nil)
        #expect(coordinator.pendingTepalUnlock == nil)
        #expect(coordinator.settings.tepalPalette == .emberMoss)
        #expect(fixture.reloadedStore().settings.tepalPalette == .emberMoss)
        #expect(coordinator.tepalVisualState.growth.tier == .flourishing)
        #expect(coordinator.tepalVisualState.palette == .emberMoss)
        #expect(coordinator.tepalVisualState.pose == .completionBloom)

        clock.advance(by: 2)
        fixture.postWake()
        try await eventually { coordinator.tepalVisualState.pose == .resting }
        fixture.postWake()
        await settle()
        #expect(coordinator.tepalVisualState.pose == .resting)
    }

    @Test func dismissTepalUnlockClearsOnlyTheBanner() async throws {
        // Break caught: dismissing an unlock reveal also resets earned growth, palette preference, or the active bloom.
        let now = Date(timeIntervalSinceReferenceDate: 1_600)
        let clock = MutableTestClock(now)
        let history = FakeHistoryRecorder(completedFocuses: 3, rewardsOnRecord: [])
        let fixture = makeFixture(
            clock: clock,
            calendar: TestCalendar(events: []),
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 60
            settings.tepalPalette = .dewdrop
        }
        let coordinator = fixture.makeCoordinator(historyRecorder: history)
        defer { fixture.cleanUp(coordinator) }
        coordinator.start()
        coordinator.startFocus()
        clock.advance(by: 60)
        coordinator.pauseOrResume()
        clock.advance(by: 2)
        fixture.postWake()
        try await eventually { coordinator.pendingTepalUnlock == .pollenGold }
        let visualState = coordinator.tepalVisualState

        coordinator.dismissTepalUnlock()

        #expect(coordinator.pendingTepalUnlock == nil)
        #expect(coordinator.tepalCompletedFocusCount == 4)
        #expect(coordinator.settings.tepalPalette == .dewdrop)
        #expect(coordinator.tepalVisualState == visualState)
    }

    @Test func laterNonmilestoneBloomKeepsAnAlreadyPublishedUnlockVisible() async throws {
        // Break caught: finishing a later bloom assigns a nil queue over an unlock the user has not dismissed.
        let now = Date(timeIntervalSinceReferenceDate: 1_650)
        let clock = MutableTestClock(now)
        let history = FakeHistoryRecorder(
            completedFocuses: 3,
            rewardsOnRecord: [.sparkle]
        )
        let fixture = makeFixture(
            clock: clock,
            calendar: TestCalendar(events: []),
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 60
        }
        let coordinator = fixture.makeCoordinator(historyRecorder: history)
        defer { fixture.cleanUp(coordinator) }
        coordinator.start()
        coordinator.startFocus()
        clock.advance(by: 60)
        coordinator.pauseOrResume()
        clock.advance(by: 2)
        fixture.postWake()
        try await eventually { coordinator.pendingTepalUnlock == .pollenGold }

        coordinator.skipPhase()
        #expect(coordinator.pomodoro.phase == .focus)
        coordinator.pauseOrResume()
        clock.advance(by: 60)
        coordinator.pauseOrResume()
        #expect(coordinator.pendingTepalUnlock == .pollenGold)

        clock.advance(by: 2)
        fixture.postWake()
        try await eventually { coordinator.tepalVisualState.pose == .resting }
        #expect(coordinator.pendingTepalUnlock == .pollenGold)
    }

    @Test func clearAllRestoresMoonFernSeedlingAndRemovesQueuedUnlock() async {
        // Break caught: Clear All hides the current banner but lets a privately queued unlock surface after reset.
        let now = Date(timeIntervalSinceReferenceDate: 1_700)
        let clock = MutableTestClock(now)
        let history = FakeHistoryRecorder(completedFocuses: 3, rewardsOnRecord: [])
        let fixture = makeFixture(
            clock: clock,
            calendar: TestCalendar(events: []),
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 60
            settings.tepalPalette = .dewdrop
        }
        let coordinator = fixture.makeCoordinator(historyRecorder: history)
        defer { fixture.cleanUp(coordinator) }
        coordinator.start()
        coordinator.startFocus()
        clock.advance(by: 60)
        coordinator.pauseOrResume()
        #expect(coordinator.pendingTepalUnlock == nil)

        coordinator.clearAllLocalData()
        clock.advance(by: 2)
        fixture.postWake()
        await settle()

        #expect(coordinator.tepalCompletedFocusCount == 0)
        #expect(coordinator.pendingTepalUnlock == nil)
        #expect(coordinator.settings.tepalPalette == .moonFern)
        #expect(coordinator.tepalVisualState.growth.tier == .seedling)
        #expect(coordinator.tepalVisualState.palette == .moonFern)
    }

    @Test func thrownCalendarRequestLeavesAnOnboardingPomodoroOnlyExit() async throws {
        // Break caught: request errors map to unavailable, whose permission page previously had no completion action.
        let calendar = TestCalendar(
            events: [],
            authorization: .notDetermined,
            requestError: TestCalendarError.requestFailed
        )
        let fixture = makeFixture(
            clock: MutableTestClock(Date(timeIntervalSinceReferenceDate: 4_000)),
            calendar: calendar,
            sleepRecorder: SleepRecorder()
        ) { _ in }
        let coordinator = fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.calendarStatus == .notRequested }

        let granted = await coordinator.requestCalendarAccess(afterExplanation: true)

        #expect(!granted)
        guard case .unavailable = coordinator.calendarStatus else {
            Issue.record("Expected a request error to remain visible as unavailable")
            return
        }
        #expect(OnboardingCalendarAccessPolicy.offersPomodoroOnly(for: coordinator.calendarStatus))
    }

    @Test func backgroundRefreshNeverPromptsButExplicitPermissionActionDoes() async throws {
        // Break caught: launch/periodic refresh accidentally triggers the first Calendar permission prompt before onboarding explains it.
        let now = Date(timeIntervalSinceReferenceDate: 5_000)
        let calendar = TestCalendar(events: [], authorization: .notDetermined)
        let fixture = makeFixture(
            clock: MutableTestClock(now),
            calendar: calendar,
            sleepRecorder: SleepRecorder()
        ) { _ in }
        let coordinator = fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.calendarStatus == .notRequested }
        #expect(await calendar.requestCount() == 0)

        let ignored = await coordinator.requestCalendarAccess(afterExplanation: false)
        #expect(!ignored)
        #expect(await calendar.requestCount() == 0)

        let granted = await coordinator.requestCalendarAccess(afterExplanation: true)

        #expect(!granted)
        #expect(await calendar.requestCount() == 1)
        #expect(coordinator.calendarStatus == .accessDenied)
    }

    @Test func refreshUsesOnlyEnabledCalendarsFromConfirmedGoogleSources() async throws {
        // Break caught: refresh reads local/iCloud calendars or ignores the user's persisted confirmed Google selection.
        let now = Date(timeIntervalSinceReferenceDate: 7_000)
        let calendars = [
            CalendarDescriptor(
                id: "google-work",
                title: "Work",
                sourceTitle: "Google",
                sourceID: "google-source",
                sourceEligibility: .requiresGoogleConfirmation
            ),
            CalendarDescriptor(
                id: "google-personal",
                title: "Personal",
                sourceTitle: "Google",
                sourceID: "google-source",
                sourceEligibility: .requiresGoogleConfirmation
            ),
            CalendarDescriptor(
                id: "icloud-home",
                title: "Home",
                sourceTitle: "iCloud",
                sourceID: "icloud-source",
                sourceEligibility: .ineligible
            ),
        ]
        let calendar = TestCalendar(events: [], calendars: calendars)
        let fixture = makeFixture(
            clock: MutableTestClock(now),
            calendar: calendar,
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.confirmedGoogleSourceIDs = ["google-source"]
            settings.enabledCalendarIDs = ["google-work"]
        }
        let coordinator = fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.calendarStatus == .ready }

        #expect(await calendar.lastRequestedCalendarIDs() == ["google-work"])
        #expect(coordinator.calendarChoices.map(\.id) == ["google-personal", "google-work"])
    }

    @Test func unconfirmedCalDAVSourceNeverReadsEventsAndReportsNoSelection() async throws {
        // Break caught: an ambiguous CalDAV source is trusted from its Google-looking name before the user confirms the account.
        let calendar = TestCalendar(
            events: [meeting(id: "private-event", start: Date(timeIntervalSinceReferenceDate: 9_000))],
            calendars: [CalendarDescriptor(
                id: "candidate-calendar",
                title: "Work",
                sourceTitle: "Google Migration Archive",
                sourceID: "misleading-source",
                sourceEligibility: .requiresGoogleConfirmation
            )]
        )
        let fixture = makeFixture(
            clock: MutableTestClock(Date(timeIntervalSinceReferenceDate: 8_000)),
            calendar: calendar,
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.confirmedGoogleSourceIDs = []
            settings.enabledCalendarIDs = ["candidate-calendar"]
        }
        let coordinator = fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.calendarStatus == .noSelection }

        #expect(coordinator.calendarChoices.map(\.id) == ["candidate-calendar"])
        #expect(coordinator.nextEvent == nil)
        #expect(await calendar.eventReadCount() == 0)
    }

    @Test func opaqueConfirmedWorkspaceSourceCanReadOnlyItsSelectedCalendar() async throws {
        // Break caught: explicit confirmation still depends on a Google/Gmail substring and rejects opaque Workspace metadata.
        let sourceID = "C8B038DD-2272-43AE-A3C7-60F0748B7C5D"
        let event = CalendarEventSummary(
            id: "workspace-event",
            title: "Workspace event",
            start: Date(timeIntervalSinceReferenceDate: 12_000),
            end: Date(timeIntervalSinceReferenceDate: 12_600),
            calendarID: "workspace-calendar",
            isAllDay: false,
            isCancelled: false
        )
        let calendar = TestCalendar(
            events: [event],
            calendars: [CalendarDescriptor(
                id: "workspace-calendar",
                title: "Primary",
                sourceTitle: "Corporate Calendar",
                sourceID: sourceID,
                sourceEligibility: .requiresGoogleConfirmation
            )]
        )
        let fixture = makeFixture(
            clock: MutableTestClock(Date(timeIntervalSinceReferenceDate: 11_000)),
            calendar: calendar,
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.confirmedGoogleSourceIDs = [sourceID]
            settings.enabledCalendarIDs = ["workspace-calendar"]
        }
        let coordinator = fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.calendarStatus == .ready }

        #expect(coordinator.nextEvent == event)
        #expect(await calendar.lastRequestedCalendarIDs() == ["workspace-calendar"])
    }

    @Test func absenceOfEligibleCalDAVSourcesReportsDisconnectedWithoutReadingEvents() async throws {
        // Break caught: full Calendar access with only local or Exchange calendars is shown as ready despite having no Google candidate.
        let calendar = TestCalendar(
            events: [],
            calendars: [CalendarDescriptor(
                id: "exchange-calendar",
                title: "Work",
                sourceTitle: "Exchange",
                sourceID: "exchange-source",
                sourceEligibility: .ineligible
            )]
        )
        let fixture = makeFixture(
            clock: MutableTestClock(Date(timeIntervalSinceReferenceDate: 13_000)),
            calendar: calendar,
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.confirmedGoogleSourceIDs = []
            settings.enabledCalendarIDs = []
        }
        let coordinator = fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.calendarStatus == .disconnected }

        #expect(coordinator.calendarChoices.isEmpty)
        #expect(await calendar.eventReadCount() == 0)
    }

    @Test func cancellingAnOverlapLeavesTheTimerIdleAndClearsThePendingWarning() async throws {
        // Break caught: the Cancel action dismisses the dialog visually but leaves stale overlap state or starts the timer.
        let now = Date(timeIntervalSinceReferenceDate: 8_000)
        let event = meeting(id: "overlap-cancel", start: now.addingTimeInterval(30))
        let calendar = TestCalendar(events: [event])
        let fixture = makeFixture(
            clock: MutableTestClock(now),
            calendar: calendar,
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 60
        }
        let coordinator = fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.nextEvent == event }
        coordinator.startFocus()
        #expect(coordinator.focusOverlap == event)

        coordinator.cancelFocusOverlap()

        #expect(coordinator.focusOverlap == nil)
        #expect(coordinator.pomodoro.phase == .idle)
    }

    @Test func dockStartWithClosedPanelShowsOverlapAndCancelLeavesIdle() async throws {
        // Break caught: Dock Start Focus creates overlap state behind a closed panel, leaving Cancel unreachable.
        let now = Date(timeIntervalSinceReferenceDate: 8_500)
        let event = meeting(id: "dock-overlap-cancel", start: now.addingTimeInterval(30))
        let fixture = makeFixture(
            clock: MutableTestClock(now),
            calendar: TestCalendar(events: [event]),
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 60
        }
        let presentation = PanelPresentationRecorder()
        let coordinator = fixture.makeCoordinator(
            ensureControlPanelPresented: { _ in presentation.ensurePresented() }
        )
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.nextEvent == event }
        coordinator.performDockPrimaryAction()

        #expect(presentation.isPresented)
        #expect(presentation.ensureCount == 1)
        #expect(coordinator.focusOverlap == event)
        coordinator.cancelFocusOverlap()
        #expect(coordinator.pomodoro.phase == .idle)
        #expect(coordinator.focusOverlap == nil)
    }

    @Test func dockStartWithClosedPanelShowsOverlapAndStartAnywayBeginsFocus() async throws {
        // Break caught: the Dock route shows a warning but its Start Anyway command is not wired to the pending idle focus.
        let now = Date(timeIntervalSinceReferenceDate: 8_700)
        let event = meeting(id: "dock-overlap-start", start: now.addingTimeInterval(30))
        let fixture = makeFixture(
            clock: MutableTestClock(now),
            calendar: TestCalendar(events: [event]),
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 60
        }
        let presentation = PanelPresentationRecorder()
        let coordinator = fixture.makeCoordinator(
            ensureControlPanelPresented: { _ in presentation.ensurePresented() }
        )
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.nextEvent == event }
        coordinator.performDockPrimaryAction()
        coordinator.startFocusIgnoringOverlap()

        #expect(presentation.isPresented)
        #expect(presentation.ensureCount == 1)
        #expect(coordinator.focusOverlap == nil)
        #expect(coordinator.pomodoro.phase == .focus)
        #expect(!coordinator.pomodoro.isPaused)
    }

    @Test func reminderSchedulerChoosesTheEarliestRunnableDeadlineAcrossOccurrences() async throws {
        // Break caught: a start-sorted snoozed occurrence hides a later occurrence whose unsnoozed alert is due first.
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let clock = MutableTestClock(now)
        let first = meeting(id: "first", start: now.addingTimeInterval(100))
        let second = meeting(id: "second", start: now.addingTimeInterval(150))
        let firstKey = ReminderOccurrenceKey(eventID: first.id, start: first.start)
        let calendar = TestCalendar(events: [first, second])
        let sleepRecorder = SleepRecorder()
        let fixture = makeFixture(clock: clock, calendar: calendar, sleepRecorder: sleepRecorder) { settings in
            settings.reminderLead = 100
        }
        fixture.store.saveReminderState(ReminderState(
            shown: [],
            snoozedUntil: [firstKey: now.addingTimeInterval(90)],
            snoozeUsed: [firstKey]
        ))
        let coordinator = fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.calendarStatus == .ready }
        try await eventually { await sleepRecorder.shortIntervals().isEmpty == false }

        let intervals = await sleepRecorder.shortIntervals()
        #expect(intervals.contains(where: { abs($0 - 50) < 0.01 }))
        #expect(!intervals.contains(where: { abs($0 - 90) < 0.01 }))
    }

    @Test func activeMeetingConsumesEverySimultaneousDeadlineWithoutAHiddenZeroDelayLoop() async throws {
        // Regression guard: simultaneous occurrences share the visible panel and leave no hidden zero-delay deadline.
        let now = Date(timeIntervalSinceReferenceDate: 20_000)
        let first = meeting(id: "first", start: now.addingTimeInterval(50))
        let second = meeting(id: "second", start: now.addingTimeInterval(50))
        let clock = MutableTestClock(now)
        let calendar = TestCalendar(events: [first, second])
        let sleepRecorder = SleepRecorder()
        let fixture = makeFixture(clock: clock, calendar: calendar, sleepRecorder: sleepRecorder) { settings in
            settings.reminderLead = 60
        }
        let excursion = ExcursionPanelController()
        let coordinator = fixture.makeCoordinator(excursionController: excursion)
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { excursion.presentedMeetingTitles.count == 2 }
        await settle()

        #expect(await sleepRecorder.shortIntervals().isEmpty)
        #expect(excursion.presentedMeetingTitles == [first.title, second.title])

        coordinator.dismissMeeting()
        await settle()
        #expect(await sleepRecorder.shortIntervals().isEmpty)
    }

    @Test func simultaneousDueOccurrencesShareOnePanelAndPersistEveryKeyBeforePresentation() async throws {
        // Break caught: the first 8-second panel suppresses a simultaneous occurrence and persistence happens only after presentation.
        let now = Date(timeIntervalSinceReferenceDate: 21_000)
        let first = meeting(id: "simultaneous-first", start: now.addingTimeInterval(5))
        let second = meeting(id: "simultaneous-second", start: now.addingTimeInterval(5))
        let expectedKeys: Set<ReminderOccurrenceKey> = [first, second].reduce(into: []) { keys, event in
            keys.insert(ReminderOccurrenceKey(eventID: event.id, start: event.start))
        }
        let fixture = makeFixture(
            clock: MutableTestClock(now),
            calendar: TestCalendar(events: [first, second]),
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.reminderLead = 60
        }
        let excursion = PersistenceInspectingExcursion()
        excursion.onMeetingPresentation = {
            excursion.shownAtPresentation = fixture.reloadedStore().loadReminderState().shown
        }
        let coordinator = fixture.makeCoordinator(excursionController: excursion)
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { excursion.presentedTitles.count == 2 }

        #expect(excursion.presentationCount == 1)
        #expect(excursion.presentedTitles == [first.title, second.title])
        #expect(excursion.shownAtPresentation == expectedKeys)
        #expect(fixture.reloadedStore().loadReminderState().shown == expectedKeys)
    }

    @Test func meetingPresentationReceivesSelectedMatureTepalAppearance() async throws {
        // Break caught: coordinator presentation drops the user's earned palette and growth before the meeting controller forces its pose.
        let now = Date(timeIntervalSinceReferenceDate: 21_500)
        let event = meeting(id: "tepal-meeting", start: now.addingTimeInterval(5))
        let fixture = makeFixture(
            clock: MutableTestClock(now),
            calendar: TestCalendar(events: [event]),
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.reminderLead = 60
            settings.tepalPalette = .frostBloom
        }
        let excursion = PersistenceInspectingExcursion()
        let coordinator = fixture.makeCoordinator(
            historyRecorder: FakeHistoryRecorder(completedFocuses: 25),
            excursionController: excursion
        )
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { excursion.presentedAppearance != nil }

        let appearance = try #require(excursion.presentedAppearance)
        #expect(appearance.pose == .meetingAttentive)
        #expect(appearance.palette == .frostBloom)
        #expect(appearance.growth.tier == .mature)
    }

    @Test func occurrenceBecomingDueDuringAnActivePanelMergesBeforeItsStart() async throws {
        // Break caught: active-panel deadline suppression loses an occurrence whose lead boundary arrives during the first panel.
        let now = Date(timeIntervalSinceReferenceDate: 22_000)
        let clock = MutableTestClock(now)
        let first = meeting(id: "visible-first", start: now.addingTimeInterval(60))
        let second = meeting(id: "due-in-four", start: now.addingTimeInterval(64))
        let excursion = ExcursionPanelController()
        let fixture = makeFixture(
            clock: clock,
            calendar: TestCalendar(events: [first, second]),
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.reminderLead = 60
        }
        let coordinator = fixture.makeCoordinator(excursionController: excursion)
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { excursion.presentedMeetingTitles == [first.title] }
        clock.advance(by: 4)
        fixture.postWake()
        try await eventually { excursion.presentedMeetingTitles.count == 2 }

        #expect(excursion.presentedMeetingTitles == [first.title, second.title])
    }

    @Test func combinedOccurrencesEachReceiveOnlyOneOptionalSnooze() async throws {
        // Break caught: combining reminders drops snooze state for one occurrence or permits a second snooze for the group.
        let now = Date(timeIntervalSinceReferenceDate: 23_000)
        let clock = MutableTestClock(now)
        let first = meeting(id: "snooze-first", start: now.addingTimeInterval(600))
        let second = meeting(id: "snooze-second", start: now.addingTimeInterval(600))
        let keys = Set([first, second].map {
            ReminderOccurrenceKey(eventID: $0.id, start: $0.start)
        })
        let sound = SoundRecorder()
        let excursion = ExcursionPanelController()
        let fixture = makeFixture(
            clock: clock,
            calendar: TestCalendar(events: [first, second]),
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.reminderLead = 600
            settings.snoozeDuration = 300
            settings.soundEnabled = true
        }
        let coordinator = fixture.makeCoordinator(
            soundPlayer: sound,
            excursionController: excursion
        )
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { excursion.presentedMeetingTitles.count == 2 }
        coordinator.snoozeMeeting()
        let afterFirstSnooze = fixture.reloadedStore().loadReminderState()
        #expect(afterFirstSnooze.snoozeUsed == keys)
        #expect(Set(afterFirstSnooze.snoozedUntil.keys) == keys)

        clock.advance(by: 300)
        fixture.postWake()
        try await eventually { excursion.presentedMeetingTitles.count == 2 }
        coordinator.snoozeMeeting()
        let afterSecondAttempt = fixture.reloadedStore().loadReminderState()

        #expect(afterSecondAttempt.snoozeUsed == keys)
        #expect(afterSecondAttempt.snoozedUntil.isEmpty)
        #expect(sound.cues == [.meetingReminder])
        #expect(!excursion.isPresented)
    }

    @Test func deniedAuthorizationRemainsDeniedAcrossLaterRefreshesWithoutPrompting() async throws {
        // Break caught: a denied first refresh is remembered as "requested" and a periodic refresh later reports ready.
        let now = Date(timeIntervalSinceReferenceDate: 30_000)
        let calendar = TestCalendar(events: [], authorization: .denied)
        let fixture = makeFixture(
            clock: MutableTestClock(now),
            calendar: calendar,
            sleepRecorder: SleepRecorder()
        ) { _ in }
        let coordinator = fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.calendarStatus == .accessDenied }
        let firstReads = await calendar.authorizationReadCount()

        coordinator.refreshCalendar()
        try await eventually { await calendar.authorizationReadCount() > firstReads }

        #expect(coordinator.calendarStatus == .accessDenied)
        #expect(await calendar.requestCount() == 0)
        #expect(await calendar.eventReadCount() == 0)
    }

    @Test func revokedAuthorizationClearsPreviouslyReadyEvents() async throws {
        // Break caught: a coordinator that was once granted skips authorization checks and retains stale event data after revocation.
        let now = Date(timeIntervalSinceReferenceDate: 40_000)
        let event = meeting(id: "revoked", start: now.addingTimeInterval(1_000))
        let calendar = TestCalendar(events: [event], authorization: .fullAccess)
        let fixture = makeFixture(
            clock: MutableTestClock(now),
            calendar: calendar,
            sleepRecorder: SleepRecorder()
        ) { _ in }
        let coordinator = fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.calendarStatus == .ready && coordinator.nextEvent == event }

        await calendar.setAuthorization(.denied)
        coordinator.refreshCalendar()
        try await eventually { coordinator.calendarStatus == .accessDenied }

        #expect(coordinator.nextEvent == nil)
        #expect(await calendar.requestCount() == 0)
    }

    @Test func restoredAuthorizationReturnsToReadyWithoutRequestingAccess() async throws {
        // Break caught: denial is cached permanently and a later System Settings grant cannot restore calendar reminders.
        let now = Date(timeIntervalSinceReferenceDate: 50_000)
        let event = meeting(id: "restored", start: now.addingTimeInterval(1_000))
        let calendar = TestCalendar(events: [event], authorization: .denied)
        let fixture = makeFixture(
            clock: MutableTestClock(now),
            calendar: calendar,
            sleepRecorder: SleepRecorder()
        ) { _ in }
        let coordinator = fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.calendarStatus == .accessDenied }

        await calendar.setAuthorization(.fullAccess)
        coordinator.refreshCalendar()
        try await eventually { coordinator.calendarStatus == .ready && coordinator.nextEvent == event }

        #expect(await calendar.requestCount() == 0)
        #expect(await calendar.eventReadCount() == 1)
    }

    @Test func refreshCancellationClosesTheActiveMeetingAndReleasesItsTitle() async throws {
        // Break caught: an already-visible reminder keeps cancelled private event content after a successful refresh.
        let now = Date(timeIntervalSinceReferenceDate: 51_000)
        let event = CalendarEventSummary(
            id: "private-cancelled",
            title: "Confidential planning",
            start: now.addingTimeInterval(60),
            end: now.addingTimeInterval(660),
            calendarID: "work",
            isAllDay: false,
            isCancelled: false
        )
        let cancelled = CalendarEventSummary(
            id: event.id,
            title: event.title,
            start: event.start,
            end: event.end,
            calendarID: event.calendarID,
            isAllDay: false,
            isCancelled: true
        )
        let calendar = TestCalendar(events: [event])
        let excursion = ExcursionPanelController()
        let fixture = makeFixture(
            clock: MutableTestClock(now),
            calendar: calendar,
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.reminderLead = 60
        }
        let coordinator = fixture.makeCoordinator(excursionController: excursion)
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { excursion.presentedMeetingTitles == [event.title] }
        await calendar.setEvents([cancelled])
        coordinator.refreshCalendar()
        try await eventually { coordinator.calendarStatus == .ready && !excursion.isPresented }

        #expect(excursion.presentedMeetingTitles.isEmpty)
        #expect(coordinator.petState != .meetingAlert)
    }

    @Test func revocationClosesTheActiveMeetingAndClearsPendingOverlap() async throws {
        // Break caught: Calendar revocation clears the list but leaves the active title/panel and overlap confirmation reachable.
        let now = Date(timeIntervalSinceReferenceDate: 52_000)
        let event = CalendarEventSummary(
            id: "private-revoked",
            title: "Private customer call",
            start: now.addingTimeInterval(60),
            end: now.addingTimeInterval(660),
            calendarID: "work",
            isAllDay: false,
            isCancelled: false
        )
        let calendar = TestCalendar(events: [event])
        let excursion = ExcursionPanelController()
        let fixture = makeFixture(
            clock: MutableTestClock(now),
            calendar: calendar,
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 120
            settings.reminderLead = 60
        }
        let coordinator = fixture.makeCoordinator(excursionController: excursion)
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { excursion.presentedMeetingTitles == [event.title] }
        coordinator.startFocus()
        #expect(coordinator.focusOverlap == event)
        await calendar.setAuthorization(.denied)
        coordinator.refreshCalendar()
        try await eventually { coordinator.calendarStatus == .accessDenied }

        #expect(!excursion.isPresented)
        #expect(excursion.presentedMeetingTitles.isEmpty)
        #expect(coordinator.focusOverlap == nil)
        #expect(coordinator.petState != .meetingAlert)
    }

    @Test func refreshMoveReplacesThePendingOverlapWithTheCurrentOccurrence() async throws {
        // Break caught: Start Anyway remains attached to a moved-away occurrence and bypasses a different current overlap.
        let now = Date(timeIntervalSinceReferenceDate: 53_000)
        let original = meeting(id: "old-overlap", start: now.addingTimeInterval(30))
        let replacement = meeting(id: "current-overlap", start: now.addingTimeInterval(45))
        let calendar = TestCalendar(events: [original])
        let fixture = makeFixture(
            clock: MutableTestClock(now),
            calendar: calendar,
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 60
            settings.meetingAlertsEnabled = false
        }
        let coordinator = fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.nextEvent == original }
        coordinator.startFocus()
        #expect(coordinator.focusOverlap == original)

        await calendar.setEvents([replacement])
        coordinator.refreshCalendar()
        try await eventually { coordinator.nextEvent == replacement }

        #expect(coordinator.focusOverlap == replacement)
    }

    @Test func refreshWithoutACurrentOverlapClearsThePendingConfirmation() async throws {
        // Break caught: a cancelled or moved-outside focus window leaves an obsolete Start Anyway action enabled.
        let now = Date(timeIntervalSinceReferenceDate: 54_000)
        let original = meeting(id: "obsolete-overlap", start: now.addingTimeInterval(30))
        let moved = meeting(id: original.id, start: now.addingTimeInterval(600))
        let calendar = TestCalendar(events: [original])
        let fixture = makeFixture(
            clock: MutableTestClock(now),
            calendar: calendar,
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 60
            settings.meetingAlertsEnabled = false
        }
        let coordinator = fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.nextEvent == original }
        coordinator.startFocus()
        #expect(coordinator.focusOverlap == original)

        await calendar.setEvents([moved])
        coordinator.refreshCalendar()
        try await eventually { coordinator.nextEvent == moved }

        #expect(coordinator.focusOverlap == nil)
    }

    @Test func eventFetchCrossingOccurrenceStartUsesThePostFetchClock() async throws {
        // Break caught: a refresh filters with its pre-fetch timestamp and presents an event that began while EventKit was suspended.
        let now = Date(timeIntervalSinceReferenceDate: 55_000)
        let clock = MutableTestClock(now)
        let calendar = TestCalendar(events: [])
        let sound = SoundRecorder()
        let excursion = ExcursionPanelController()
        let fixture = makeFixture(
            clock: clock,
            calendar: calendar,
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.reminderLead = 60
            settings.soundEnabled = true
        }
        let coordinator = fixture.makeCoordinator(
            soundPlayer: sound,
            excursionController: excursion
        )
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.calendarStatus == .ready }
        await calendar.setEvents([meeting(
            id: "started-during-fetch",
            start: now.addingTimeInterval(30)
        )])
        await calendar.suspendNextEventFetch()
        coordinator.refreshCalendar()
        try await eventually { await calendar.isEventFetchSuspended }

        clock.advance(by: 31)
        await calendar.resumeEventFetch()
        try await eventually { coordinator.calendarStatus == .ready }

        #expect(coordinator.nextEvent == nil)
        #expect(sound.cues.isEmpty)
        #expect(!excursion.isPresented)
    }

    @Test func wakeRefreshRejectsACancelledOccurrenceBeforeReminderEvaluation() async throws {
        // Break caught: wake evaluates a cached due occurrence before learning that it was cancelled during sleep.
        let now = Date(timeIntervalSinceReferenceDate: 56_000)
        let clock = MutableTestClock(now)
        let original = meeting(id: "cancelled-asleep", start: now.addingTimeInterval(1_000))
        let cancelled = CalendarEventSummary(
            id: original.id,
            title: original.title,
            start: original.start,
            end: original.end,
            calendarID: original.calendarID,
            isAllDay: false,
            isCancelled: true
        )
        let calendar = TestCalendar(events: [original])
        let sound = SoundRecorder()
        let fixture = makeFixture(
            clock: clock,
            calendar: calendar,
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.reminderLead = 100
            settings.soundEnabled = true
        }
        let coordinator = fixture.makeCoordinator(soundPlayer: sound)
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.calendarStatus == .ready }
        await calendar.setEvents([cancelled])
        clock.advance(by: 950)

        fixture.postWake()
        try await eventually { await calendar.eventReadCount() >= 2 }
        try await eventually { coordinator.calendarStatus == .ready }

        #expect(coordinator.nextEvent == nil)
        #expect(sound.cues.isEmpty)
    }

    @Test func wakeRefreshUsesAMovedOccurrenceBeforeReminderEvaluation() async throws {
        // Break caught: wake presents the old occurrence key/title before accepting a move made during sleep.
        let now = Date(timeIntervalSinceReferenceDate: 57_000)
        let clock = MutableTestClock(now)
        let original = meeting(id: "moved-asleep", start: now.addingTimeInterval(1_000))
        let moved = meeting(id: original.id, start: now.addingTimeInterval(2_000))
        let calendar = TestCalendar(events: [original])
        let sound = SoundRecorder()
        let fixture = makeFixture(
            clock: clock,
            calendar: calendar,
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.reminderLead = 100
            settings.soundEnabled = true
        }
        let coordinator = fixture.makeCoordinator(soundPlayer: sound)
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.nextEvent == original }
        await calendar.setEvents([moved])
        clock.advance(by: 950)

        fixture.postWake()
        try await eventually { coordinator.nextEvent == moved }

        #expect(sound.cues.isEmpty)
    }

    @Test func wakeRefreshBlocksCachedReminderEvaluationUntilFreshEventsArrive() async throws {
        // Break caught: a timer/user command can evaluate cached due events while wake refresh is still awaiting EventKit.
        let now = Date(timeIntervalSinceReferenceDate: 58_000)
        let clock = MutableTestClock(now)
        let stale = meeting(id: "stale-while-waking", start: now.addingTimeInterval(120))
        let calendar = TestCalendar(events: [stale])
        let excursion = ExcursionPanelController()
        let fixture = makeFixture(
            clock: clock,
            calendar: calendar,
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.reminderLead = 60
        }
        let coordinator = fixture.makeCoordinator(excursionController: excursion)
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.calendarStatus == .ready }
        await calendar.setEvents([])
        await calendar.suspendNextEventFetch()
        clock.advance(by: 60)
        fixture.postWake()
        try await eventually { await calendar.isEventFetchSuspended }

        coordinator.startFocusIgnoringOverlap()
        await settle()

        #expect(excursion.presentedMeetingTitles.isEmpty)
        #expect(coordinator.petState == .focus)

        await calendar.resumeEventFetch()
        try await eventually { coordinator.calendarStatus == .ready }
        #expect(excursion.presentedMeetingTitles.isEmpty)
    }

    @Test func newlyStagedManualFocusChecksOverlapBeforeStarting() async throws {
        // Break caught: skip-to-focus stages a fresh paused countdown, but pauseOrResume bypasses the overlap policy.
        let now = Date(timeIntervalSinceReferenceDate: 60_000)
        let event = meeting(id: "manual-boundary", start: now.addingTimeInterval(30))
        let calendar = TestCalendar(events: [])
        let fixture = makeFixture(
            clock: MutableTestClock(now),
            calendar: calendar,
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 60
            settings.meetingAlertsEnabled = false
        }
        let coordinator = fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.calendarStatus == .ready }
        coordinator.startFocus()
        coordinator.skipPhase()
        coordinator.skipPhase()
        #expect(coordinator.pomodoro.phase == .focus)
        #expect(coordinator.pomodoro.isPaused)

        await calendar.setEvents([event])
        coordinator.refreshCalendar()
        try await eventually { coordinator.nextEvent == event }
        coordinator.pauseOrResume()

        #expect(coordinator.pomodoro.isPaused)
        #expect(coordinator.focusOverlap == event)
    }

    @Test func interruptedFocusResumesWithoutBeingTreatedAsANewCountdown() async throws {
        // Break caught: overlap checks for fresh focus periods must not trap a user resuming the same interrupted period.
        let now = Date(timeIntervalSinceReferenceDate: 70_000)
        let event = meeting(id: "interrupted", start: now.addingTimeInterval(30))
        let calendar = TestCalendar(events: [])
        let fixture = makeFixture(
            clock: MutableTestClock(now),
            calendar: calendar,
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 60
            settings.meetingAlertsEnabled = false
        }
        let coordinator = fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.calendarStatus == .ready }
        coordinator.startFocus()
        coordinator.pauseOrResume()
        await calendar.setEvents([event])
        coordinator.refreshCalendar()
        try await eventually { coordinator.nextEvent == event }

        coordinator.pauseOrResume()

        #expect(!coordinator.pomodoro.isPaused)
        #expect(coordinator.pomodoro.targetEnd != nil)
        #expect(coordinator.focusOverlap == nil)
    }

    @Test func pauseAtExpiredFocusRecordsHistoryAndShowsTheEarnedReward() async throws {
        // Break caught: coordinator Pause at the expired target erases the completion, history entry, and reward transition.
        let now = Date(timeIntervalSinceReferenceDate: 72_000)
        let clock = MutableTestClock(now)
        let history = FakeHistoryRecorder()
        let fixture = makeFixture(
            clock: clock,
            calendar: TestCalendar(events: []),
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 60
        }
        let coordinator = fixture.makeCoordinator(historyRecorder: history)
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        coordinator.startFocus()
        clock.advance(by: 60)

        coordinator.pauseOrResume()

        #expect(coordinator.pomodoro.phase == .shortBreak)
        #expect(coordinator.pomodoro.completedFocusCount == 1)
        #expect(history.recordCount == 1)
        #expect(coordinator.petState == .reward)
    }

    @Test func skipAfterExpiredFourthFocusPreservesLongBreakCadenceAndReward() async throws {
        // Break caught: coordinator Skip after the target treats the fourth focus as abandoned and chooses a short break without a reward.
        let now = Date(timeIntervalSinceReferenceDate: 73_000)
        let clock = MutableTestClock(now)
        let history = FakeHistoryRecorder()
        let fixture = makeFixture(
            clock: clock,
            calendar: TestCalendar(events: []),
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 60
            settings.longBreakEvery = 4
        }
        fixture.store.saveTimerRecovery(PomodoroRecovery(
            snapshot: PomodoroSnapshot(
                phase: .focus,
                remaining: .seconds(60),
                targetEnd: now.addingTimeInterval(60),
                completedFocusCount: 3,
                isPaused: false
            ),
            focusStartDisposition: .interrupted
        ))
        let coordinator = fixture.makeCoordinator(historyRecorder: history)
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        clock.advance(by: 65)

        coordinator.skipPhase()

        #expect(coordinator.pomodoro.phase == .longBreak)
        #expect(coordinator.pomodoro.completedFocusCount == 4)
        #expect(history.recordCount == 1)
        #expect(coordinator.petState == .reward)
    }

    @Test func stagedFocusStillChecksOverlapAfterRelaunch() async throws {
        // Break caught: relaunch drops the staged-focus disposition, so a fresh paused countdown resumes as interrupted.
        let now = Date(timeIntervalSinceReferenceDate: 75_000)
        let event = meeting(id: "recovered-staged", start: now.addingTimeInterval(30))
        let calendar = TestCalendar(events: [])
        let fixture = makeFixture(
            clock: MutableTestClock(now),
            calendar: calendar,
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 60
            settings.meetingAlertsEnabled = false
        }
        let firstCoordinator = fixture.makeCoordinator()
        firstCoordinator.start()
        try await eventually { firstCoordinator.calendarStatus == .ready }
        firstCoordinator.startFocus()
        firstCoordinator.skipPhase()
        firstCoordinator.skipPhase()
        #expect(firstCoordinator.pomodoro.phase == .focus)
        #expect(firstCoordinator.pomodoro.isPaused)
        firstCoordinator.terminate()

        await calendar.setEvents([event])
        let recoveredCoordinator = fixture.makeCoordinator(
            settingsStore: fixture.reloadedStore()
        )
        defer { fixture.cleanUp(recoveredCoordinator) }
        recoveredCoordinator.start()
        try await eventually {
            recoveredCoordinator.calendarStatus == .ready
                && recoveredCoordinator.nextEvent == event
        }

        recoveredCoordinator.pauseOrResume()

        #expect(recoveredCoordinator.pomodoro.isPaused)
        #expect(recoveredCoordinator.focusOverlap == event)
    }

    @Test func interruptedFocusStillResumesNormallyAfterRelaunch() async throws {
        // Break caught: persisting fresh-focus disposition must not relabel a genuinely interrupted countdown as staged.
        let now = Date(timeIntervalSinceReferenceDate: 77_000)
        let event = meeting(id: "recovered-interrupted", start: now.addingTimeInterval(30))
        let calendar = TestCalendar(events: [])
        let fixture = makeFixture(
            clock: MutableTestClock(now),
            calendar: calendar,
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 60
            settings.meetingAlertsEnabled = false
        }
        let firstCoordinator = fixture.makeCoordinator()
        firstCoordinator.start()
        try await eventually { firstCoordinator.calendarStatus == .ready }
        firstCoordinator.startFocus()
        firstCoordinator.pauseOrResume()
        #expect(firstCoordinator.pomodoro.phase == .focus)
        #expect(firstCoordinator.pomodoro.isPaused)
        firstCoordinator.terminate()

        await calendar.setEvents([event])
        let recoveredCoordinator = fixture.makeCoordinator(
            settingsStore: fixture.reloadedStore()
        )
        defer { fixture.cleanUp(recoveredCoordinator) }
        recoveredCoordinator.start()
        try await eventually {
            recoveredCoordinator.calendarStatus == .ready
                && recoveredCoordinator.nextEvent == event
        }

        recoveredCoordinator.pauseOrResume()

        #expect(!recoveredCoordinator.pomodoro.isPaused)
        #expect(recoveredCoordinator.pomodoro.targetEnd != nil)
        #expect(recoveredCoordinator.focusOverlap == nil)
    }

    @Test func ambiguousLegacyPausedFocusRequiresOverlapConfirmation() async throws {
        // Break caught: snapshot-only paused focus is migrated as interrupted and can silently bypass an overlap.
        let now = Date(timeIntervalSinceReferenceDate: 78_000)
        let event = meeting(id: "legacy-ambiguous", start: now.addingTimeInterval(30))
        let fixture = makeFixture(
            clock: MutableTestClock(now),
            calendar: TestCalendar(events: [event]),
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 60
            settings.meetingAlertsEnabled = false
        }
        try fixture.saveLegacyRecovery(PomodoroSnapshot(
            phase: .focus,
            remaining: .seconds(60),
            targetEnd: nil,
            completedFocusCount: 2,
            isPaused: true
        ))
        let coordinator = fixture.makeCoordinator(
            settingsStore: fixture.reloadedStore()
        )
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually {
            coordinator.calendarStatus == .ready && coordinator.nextEvent == event
        }
        coordinator.pauseOrResume()

        #expect(coordinator.pomodoro.isPaused)
        #expect(coordinator.focusOverlap == event)
    }

    @Test func legacyInterruptedFocusWithoutOverlapStillResumes() async throws {
        // Break caught: conservative legacy migration must preserve a valid paused session and allow safe resume.
        let now = Date(timeIntervalSinceReferenceDate: 79_000)
        let fixture = makeFixture(
            clock: MutableTestClock(now),
            calendar: TestCalendar(events: []),
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 60
            settings.meetingAlertsEnabled = false
        }
        try fixture.saveLegacyRecovery(PomodoroSnapshot(
            phase: .focus,
            remaining: .seconds(42),
            targetEnd: nil,
            completedFocusCount: 2,
            isPaused: true
        ))
        let coordinator = fixture.makeCoordinator(
            settingsStore: fixture.reloadedStore()
        )
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.calendarStatus == .ready }
        coordinator.pauseOrResume()

        #expect(!coordinator.pomodoro.isPaused)
        #expect(coordinator.pomodoro.remaining == .seconds(42))
        #expect(coordinator.focusOverlap == nil)
    }

    @Test func autoStartedFocusBoundaryChecksOverlapBeforeCountdownBegins() async throws {
        // Break caught: an automatically advanced break starts focus immediately without consulting the overlap policy.
        let now = Date(timeIntervalSinceReferenceDate: 80_000)
        let clock = MutableTestClock(now)
        let event = meeting(id: "auto-boundary", start: now.addingTimeInterval(90))
        let calendar = TestCalendar(events: [])
        let fixture = makeFixture(
            clock: clock,
            calendar: calendar,
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 60
            settings.shortBreakDuration = 60
            settings.autoStartNextPhase = true
            settings.meetingAlertsEnabled = false
        }
        let coordinator = fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.calendarStatus == .ready }
        coordinator.startFocus()
        coordinator.skipPhase()
        #expect(coordinator.pomodoro.phase == .shortBreak)
        #expect(!coordinator.pomodoro.isPaused)

        await calendar.setEvents([event])
        coordinator.refreshCalendar()
        try await eventually { coordinator.nextEvent == event }
        clock.advance(by: 60)
        fixture.postWake()
        try await eventually { coordinator.pomodoro.phase == .focus }

        #expect(coordinator.pomodoro.isPaused)
        #expect(coordinator.focusOverlap == event)
    }

    @Test func wakeAutoStartedFocusResumesWhenCachedOverlapWasCancelled() async throws {
        // Break caught: fresh Calendar resumes the deferred focus but its first activation remains silent.
        let now = Date(timeIntervalSinceReferenceDate: 81_000)
        let clock = MutableTestClock(now)
        let original = meeting(id: "wake-auto-cancelled", start: now.addingTimeInterval(90))
        let cancelled = CalendarEventSummary(
            id: original.id,
            title: original.title,
            start: original.start,
            end: original.end,
            calendarID: original.calendarID,
            isAllDay: false,
            isCancelled: true
        )
        let calendar = TestCalendar(events: [])
        let sound = SoundRecorder()
        let fixture = makeFixture(
            clock: clock,
            calendar: calendar,
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 60
            settings.shortBreakDuration = 60
            settings.autoStartNextPhase = true
            settings.meetingAlertsEnabled = false
            settings.soundEnabled = true
        }
        let coordinator = fixture.makeCoordinator(soundPlayer: sound)
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.calendarStatus == .ready }
        coordinator.startFocus()
        coordinator.skipPhase()
        await calendar.setEvents([original])
        coordinator.refreshCalendar()
        try await eventually { coordinator.nextEvent == original }

        let readsBeforeWake = await calendar.eventReadCount()
        await calendar.setEvents([cancelled])
        clock.advance(by: 60)
        fixture.postWake()
        try await eventually {
            await calendar.eventReadCount() > readsBeforeWake
                && coordinator.calendarStatus == .ready
                && coordinator.pomodoro.phase == .focus
                && !coordinator.pomodoro.isPaused
        }

        #expect(coordinator.focusOverlap == nil)
        #expect(coordinator.pomodoro.targetEnd == clock.now.addingTimeInterval(60))
        #expect(sound.cues == [.focusStarted, .focusStarted])
        let recovery = try #require(fixture.reloadedStore().loadTimerRecovery())
        #expect(recovery.focusStartDisposition == .interrupted)
    }

    @Test func wakeAutoStartedFocusResumesWhenCachedOverlapMovedOutsideFocusWindow() async throws {
        // Break caught: a moved occurrence is no longer visible, but its cached overlap pause still blocks the countdown.
        let now = Date(timeIntervalSinceReferenceDate: 82_000)
        let clock = MutableTestClock(now)
        let original = meeting(id: "wake-auto-moved-away", start: now.addingTimeInterval(90))
        let moved = meeting(id: original.id, start: now.addingTimeInterval(600))
        let calendar = TestCalendar(events: [])
        let fixture = makeFixture(
            clock: clock,
            calendar: calendar,
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 60
            settings.shortBreakDuration = 60
            settings.autoStartNextPhase = true
            settings.meetingAlertsEnabled = false
        }
        let coordinator = fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.calendarStatus == .ready }
        coordinator.startFocus()
        coordinator.skipPhase()
        await calendar.setEvents([original])
        coordinator.refreshCalendar()
        try await eventually { coordinator.nextEvent == original }

        let readsBeforeWake = await calendar.eventReadCount()
        await calendar.setEvents([moved])
        clock.advance(by: 60)
        fixture.postWake()
        try await eventually {
            await calendar.eventReadCount() > readsBeforeWake
                && coordinator.calendarStatus == .ready
                && coordinator.pomodoro.phase == .focus
                && !coordinator.pomodoro.isPaused
        }

        #expect(coordinator.nextEvent == moved)
        #expect(coordinator.focusOverlap == nil)
        #expect(coordinator.pomodoro.targetEnd == clock.now.addingTimeInterval(60))
    }

    @Test func wakeAutoStartedFocusStaysPausedForRetainedFreshOverlap() async throws {
        // Break caught: a confirmed overlap either resumes the timer or plays a second start cue while focus remains paused.
        let now = Date(timeIntervalSinceReferenceDate: 83_000)
        let clock = MutableTestClock(now)
        let event = meeting(id: "wake-auto-retained", start: now.addingTimeInterval(90))
        let calendar = TestCalendar(events: [])
        let sound = SoundRecorder()
        let fixture = makeFixture(
            clock: clock,
            calendar: calendar,
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 60
            settings.shortBreakDuration = 60
            settings.autoStartNextPhase = true
            settings.meetingAlertsEnabled = false
            settings.soundEnabled = true
        }
        let coordinator = fixture.makeCoordinator(soundPlayer: sound)
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.calendarStatus == .ready }
        coordinator.startFocus()
        coordinator.skipPhase()
        await calendar.setEvents([event])
        coordinator.refreshCalendar()
        try await eventually { coordinator.nextEvent == event }

        let readsBeforeWake = await calendar.eventReadCount()
        clock.advance(by: 60)
        fixture.postWake()
        try await eventually {
            await calendar.eventReadCount() > readsBeforeWake
                && coordinator.calendarStatus == .ready
                && coordinator.pomodoro.phase == .focus
                && coordinator.focusOverlap == event
        }

        #expect(coordinator.pomodoro.isPaused)
        #expect(coordinator.pomodoro.targetEnd == nil)
        #expect(sound.cues == [.focusStarted])
        let recovery = try #require(fixture.reloadedStore().loadTimerRecovery())
        #expect(recovery.focusStartDisposition == .needsOverlapConfirmation)
    }

    @Test func wakeAutoStartedFocusUsesChangedFreshOverlapAndStaysPaused() async throws {
        // Break caught: wake keeps the cached warning instead of reconciling to the changed overlapping occurrence.
        let now = Date(timeIntervalSinceReferenceDate: 84_000)
        let clock = MutableTestClock(now)
        let original = meeting(id: "wake-auto-changed", start: now.addingTimeInterval(90))
        let changed = meeting(id: original.id, start: now.addingTimeInterval(100))
        let calendar = TestCalendar(events: [])
        let fixture = makeFixture(
            clock: clock,
            calendar: calendar,
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 60
            settings.shortBreakDuration = 60
            settings.autoStartNextPhase = true
            settings.meetingAlertsEnabled = false
        }
        let coordinator = fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.calendarStatus == .ready }
        coordinator.startFocus()
        coordinator.skipPhase()
        await calendar.setEvents([original])
        coordinator.refreshCalendar()
        try await eventually { coordinator.nextEvent == original }

        await calendar.setEvents([changed])
        clock.advance(by: 60)
        fixture.postWake()
        try await eventually {
            coordinator.calendarStatus == .ready
                && coordinator.pomodoro.phase == .focus
                && coordinator.focusOverlap == changed
        }

        #expect(coordinator.pomodoro.isPaused)
        #expect(coordinator.pomodoro.targetEnd == nil)
    }

    @Test func wakeRefreshNeverResumesAnInterruptedUserPause() async throws {
        // Break caught: clearing any stale overlap after wake resumes a focus that the user explicitly paused.
        let now = Date(timeIntervalSinceReferenceDate: 85_000)
        let clock = MutableTestClock(now)
        let original = meeting(id: "wake-user-paused", start: now.addingTimeInterval(30))
        let cancelled = CalendarEventSummary(
            id: original.id,
            title: original.title,
            start: original.start,
            end: original.end,
            calendarID: original.calendarID,
            isAllDay: false,
            isCancelled: true
        )
        let calendar = TestCalendar(events: [])
        let fixture = makeFixture(
            clock: clock,
            calendar: calendar,
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 60
            settings.autoStartNextPhase = true
            settings.meetingAlertsEnabled = false
        }
        let coordinator = fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.calendarStatus == .ready }
        coordinator.startFocus()
        coordinator.pauseOrResume()
        #expect(coordinator.pomodoro.isPaused)

        await calendar.setEvents([original])
        coordinator.refreshCalendar()
        try await eventually { coordinator.nextEvent == original }
        let readsBeforeWake = await calendar.eventReadCount()
        await calendar.setEvents([cancelled])
        clock.advance(by: 10)
        fixture.postWake()
        try await eventually {
            await calendar.eventReadCount() > readsBeforeWake
                && coordinator.calendarStatus == .ready
                && coordinator.nextEvent == nil
        }

        #expect(coordinator.pomodoro.isPaused)
        #expect(coordinator.pomodoro.remaining == .seconds(60))
        #expect(coordinator.pomodoro.targetEnd == nil)
        #expect(coordinator.focusOverlap == nil)
        let recovery = try #require(fixture.reloadedStore().loadTimerRecovery())
        #expect(recovery.focusStartDisposition == .interrupted)
    }

    @Test func wakeRefreshNeverResumesANewManuallyStagedFocus() async throws {
        // Break caught: a wake transition to a manual-start focus is mistaken for an overlap-paused auto-start.
        let now = Date(timeIntervalSinceReferenceDate: 86_000)
        let clock = MutableTestClock(now)
        let original = meeting(id: "wake-manual-staged", start: now.addingTimeInterval(90))
        let cancelled = CalendarEventSummary(
            id: original.id,
            title: original.title,
            start: original.start,
            end: original.end,
            calendarID: original.calendarID,
            isAllDay: false,
            isCancelled: true
        )
        let calendar = TestCalendar(events: [])
        let fixture = makeFixture(
            clock: clock,
            calendar: calendar,
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 60
            settings.shortBreakDuration = 60
            settings.autoStartNextPhase = false
            settings.meetingAlertsEnabled = false
        }
        let coordinator = fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.calendarStatus == .ready }
        coordinator.startFocus()
        coordinator.skipPhase()
        coordinator.pauseOrResume()
        #expect(coordinator.pomodoro.phase == .shortBreak)
        #expect(!coordinator.pomodoro.isPaused)

        await calendar.setEvents([original])
        coordinator.refreshCalendar()
        try await eventually { coordinator.nextEvent == original }
        let readsBeforeWake = await calendar.eventReadCount()
        await calendar.setEvents([cancelled])
        clock.advance(by: 60)
        fixture.postWake()
        try await eventually {
            await calendar.eventReadCount() > readsBeforeWake
                && coordinator.calendarStatus == .ready
                && coordinator.pomodoro.phase == .focus
        }

        #expect(coordinator.pomodoro.isPaused)
        #expect(coordinator.pomodoro.remaining == .seconds(60))
        #expect(coordinator.pomodoro.targetEnd == nil)
        #expect(coordinator.focusOverlap == nil)
        let recovery = try #require(fixture.reloadedStore().loadTimerRecovery())
        #expect(recovery.focusStartDisposition == .needsOverlapConfirmation)
    }

    @Test func rewardUnlockedBehindMeetingGetsAFullReactionExactlyOnceAfterDismissal() async throws {
        // Break caught: the real-time reward timer elapses invisibly behind a meeting and never gives the pet its reaction.
        let now = Date(timeIntervalSinceReferenceDate: 90_000)
        let clock = MutableTestClock(now)
        let event = meeting(id: "reward-meeting", start: now.addingTimeInterval(120))
        let calendar = TestCalendar(events: [event])
        let history = FakeHistoryRecorder()
        let fixture = makeFixture(
            clock: clock,
            calendar: calendar,
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 60
            settings.reminderLead = 60
        }
        let coordinator = fixture.makeCoordinator(historyRecorder: history)
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.calendarStatus == .ready }
        coordinator.startFocus()

        // The focus completion and the reminder-lead boundary occur on this same wake.
        clock.advance(by: 60)
        fixture.postWake()
        try await eventually {
            coordinator.pomodoro.phase == .shortBreak
                && coordinator.petState == .meetingAlert
        }
        #expect(coordinator.petState == .meetingAlert)
        #expect(history.recordCount == 1)

        coordinator.dismissMeeting()
        #expect(coordinator.petState == .reward)
        #expect(history.recordCount == 1)

        clock.advance(by: 1)
        fixture.postWake()
        await settle()
        #expect(coordinator.petState == .reward)

        clock.advance(by: 1)
        fixture.postWake()
        try await eventually { coordinator.petState == .rest }
        fixture.postWake()
        await settle()
        #expect(coordinator.petState == .rest)
        #expect(history.recordCount == 1)
    }

    @Test func meetingInterruptedBloomPublishesUnlockOnlyAfterTheResumedBloomFinishes() async throws {
        // Break caught: a meeting interruption exposes the queued palette while the completion bloom is paused or resumed.
        let now = Date(timeIntervalSinceReferenceDate: 92_000)
        let clock = MutableTestClock(now)
        let event = meeting(id: "unlock-after-meeting", start: now.addingTimeInterval(62))
        let calendar = TestCalendar(events: [event])
        let history = FakeHistoryRecorder(
            completedFocuses: 3,
            rewardsOnRecord: [.sparkle]
        )
        let fixture = makeFixture(
            clock: clock,
            calendar: calendar,
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 60
            settings.reminderLead = 1
        }
        let coordinator = fixture.makeCoordinator(historyRecorder: history)
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.calendarStatus == .ready }
        coordinator.startFocus()
        clock.advance(by: 60)
        fixture.postWake()
        try await eventually { coordinator.tepalVisualState.pose == .completionBloom }
        #expect(coordinator.pendingTepalUnlock == nil)

        clock.advance(by: 1)
        fixture.postWake()
        try await eventually { coordinator.petState == .meetingAlert }
        #expect(coordinator.pendingTepalUnlock == nil)

        clock.advance(by: 10)
        coordinator.dismissMeeting()
        #expect(coordinator.tepalVisualState.pose == .completionBloom)
        #expect(coordinator.pendingTepalUnlock == nil)

        clock.advance(by: 1)
        fixture.postWake()
        try await eventually {
            coordinator.tepalVisualState.pose == .resting
                && coordinator.pendingTepalUnlock == .pollenGold
        }
    }

    @Test func enabledSoundPlaysOnceForFocusCompletionAndNeverForRepeatedSettlement() async throws {
        // Break caught: start/completion feedback is missing or repeated lifecycle settlement plays completion twice.
        let now = Date(timeIntervalSinceReferenceDate: 95_000)
        let clock = MutableTestClock(now)
        let sound = SoundRecorder()
        let fixture = makeFixture(
            clock: clock,
            calendar: TestCalendar(events: []),
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 60
            settings.meetingAlertsEnabled = false
            settings.soundEnabled = true
        }
        let coordinator = fixture.makeCoordinator(soundPlayer: sound)
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        coordinator.startFocus()
        clock.advance(by: 60)
        fixture.postWake()
        try await eventually { coordinator.pomodoro.completedFocusCount == 1 }
        fixture.postWake()
        await settle()

        #expect(sound.cues == [.focusStarted, .focusCompleted])
    }

    @Test func focusStartSoundWaitsForARealRunningFocusTransition() async throws {
        // Break caught: merely requesting an overlapping focus plays a start cue while the timer remains idle.
        let now = Date(timeIntervalSinceReferenceDate: 95_500)
        let event = meeting(id: "silent-overlap", start: now.addingTimeInterval(30))
        let sound = SoundRecorder()
        let fixture = makeFixture(
            clock: MutableTestClock(now),
            calendar: TestCalendar(events: [event]),
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 60
            settings.meetingAlertsEnabled = false
            settings.soundEnabled = true
        }
        let coordinator = fixture.makeCoordinator(soundPlayer: sound)
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.nextEvent == event }
        coordinator.startFocus()

        #expect(coordinator.pomodoro.phase == .idle)
        #expect(sound.cues.isEmpty)

        coordinator.startFocusIgnoringOverlap()

        #expect(coordinator.pomodoro.phase == .focus)
        #expect(!coordinator.pomodoro.isPaused)
        #expect(sound.cues == [.focusStarted])
    }

    @Test func stagedFocusStartAnywayCuesOnceButOrdinaryResumeStaysSilent() async throws {
        // Break caught: a staged focus's first activation is mistaken for an ordinary same-phase resume and remains silent.
        let now = Date(timeIntervalSinceReferenceDate: 95_625)
        let event = meeting(id: "staged-start-anyway", start: now.addingTimeInterval(30))
        let calendar = TestCalendar(events: [])
        let sound = SoundRecorder()
        let fixture = makeFixture(
            clock: MutableTestClock(now),
            calendar: calendar,
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 60
            settings.meetingAlertsEnabled = false
            settings.soundEnabled = true
        }
        let coordinator = fixture.makeCoordinator(soundPlayer: sound)
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.calendarStatus == .ready }
        coordinator.startFocus()
        coordinator.skipPhase()
        coordinator.skipPhase()
        #expect(coordinator.pomodoro.phase == .focus)
        #expect(coordinator.pomodoro.isPaused)

        await calendar.setEvents([event])
        coordinator.refreshCalendar()
        try await eventually { coordinator.nextEvent == event }
        coordinator.pauseOrResume()
        #expect(coordinator.focusOverlap == event)
        #expect(sound.cues == [.focusStarted])

        coordinator.startFocusIgnoringOverlap()
        #expect(!coordinator.pomodoro.isPaused)
        #expect(sound.cues == [.focusStarted, .focusStarted])

        coordinator.pauseOrResume()
        coordinator.pauseOrResume()
        #expect(!coordinator.pomodoro.isPaused)
        #expect(sound.cues == [.focusStarted, .focusStarted])
    }

    @Test func defaultSoundSettingKeepsFocusStartSilent() {
        // Break caught: adding focus-start feedback changes the product's sound-off default into an audible start.
        let sound = SoundRecorder()
        let fixture = makeFixture(
            clock: MutableTestClock(Date(timeIntervalSinceReferenceDate: 95_750)),
            calendar: TestCalendar(events: []),
            sleepRecorder: SleepRecorder()
        ) { _ in }
        let coordinator = fixture.makeCoordinator(soundPlayer: sound)
        defer { fixture.cleanUp(coordinator) }

        #expect(!coordinator.settings.soundEnabled)
        coordinator.startFocus()

        #expect(coordinator.pomodoro.phase == .focus)
        #expect(sound.cues.isEmpty)
    }

    @Test func disabledSoundSuppressesFocusCompletionAndInitialMeetingCues() async throws {
        // Break caught: local AppKit sound ignores the default-off setting for either timer or meeting alerts.
        let now = Date(timeIntervalSinceReferenceDate: 96_000)
        let clock = MutableTestClock(now)
        let sound = SoundRecorder()
        let event = meeting(id: "silent-meeting", start: now.addingTimeInterval(60))
        let fixture = makeFixture(
            clock: clock,
            calendar: TestCalendar(events: [event]),
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 60
            settings.reminderLead = 60
            settings.soundEnabled = false
        }
        let coordinator = fixture.makeCoordinator(soundPlayer: sound)
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        coordinator.startFocus()
        clock.advance(by: 60)
        fixture.postWake()
        try await eventually { coordinator.pomodoro.completedFocusCount == 1 }

        #expect(sound.cues.isEmpty)
    }

    @Test func initialMeetingSoundPlaysOnceAndSnoozedPresentationIsSilent() async throws {
        // Break caught: an initial reminder is silent or its one snoozed presentation produces a duplicate sound.
        let now = Date(timeIntervalSinceReferenceDate: 97_000)
        let clock = MutableTestClock(now)
        let sound = SoundRecorder()
        let event = meeting(id: "audible-meeting", start: now.addingTimeInterval(600))
        let fixture = makeFixture(
            clock: clock,
            calendar: TestCalendar(events: [event]),
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.reminderLead = 600
            settings.snoozeDuration = 300
            settings.soundEnabled = true
        }
        let coordinator = fixture.makeCoordinator(soundPlayer: sound)
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.petState == .meetingAlert }
        #expect(sound.cues == [.meetingReminder])

        coordinator.snoozeMeeting()
        clock.advance(by: 300)
        fixture.postWake()
        try await eventually { coordinator.petState == .meetingAlert }
        coordinator.refreshCalendar()
        await settle()

        #expect(sound.cues == [.meetingReminder])
    }

    @Test func meetingMidRewardPausesAndResumesOnlyTheRemainingReaction() async throws {
        // Break caught: meeting interruption ends the active reward, then dismissal replays a second full reaction.
        let now = Date(timeIntervalSinceReferenceDate: 100_000)
        let clock = MutableTestClock(now)
        let event = meeting(id: "mid-reward", start: now.addingTimeInterval(121))
        let history = FakeHistoryRecorder()
        let fixture = makeFixture(
            clock: clock,
            calendar: TestCalendar(events: [event]),
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 60
            settings.reminderLead = 60
        }
        let coordinator = fixture.makeCoordinator(historyRecorder: history)
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.calendarStatus == .ready }
        coordinator.startFocus()
        clock.advance(by: 60)
        fixture.postWake()
        try await eventually { coordinator.petState == .reward }

        clock.advance(by: 1)
        fixture.postWake()
        try await eventually { coordinator.petState == .meetingAlert }
        clock.advance(by: 100)
        fixture.postWake()
        await settle()
        #expect(coordinator.petState == .meetingAlert)

        coordinator.dismissMeeting()
        #expect(coordinator.petState == .reward)
        clock.advance(by: 0.5)
        fixture.postWake()
        await settle()
        #expect(coordinator.petState == .reward)

        clock.advance(by: 0.5)
        fixture.postWake()
        try await eventually { coordinator.petState == .rest }
        #expect(history.recordCount == 1)
    }

    @Test func meetingAtExactRewardEndDoesNotReplayTheReactionAfterDismissal() async throws {
        // Break caught: exact-end ordering converts an elapsed reward into pending state before the due check can end it.
        let now = Date(timeIntervalSinceReferenceDate: 110_000)
        let clock = MutableTestClock(now)
        let event = meeting(id: "reward-end", start: now.addingTimeInterval(122))
        let history = FakeHistoryRecorder()
        let fixture = makeFixture(
            clock: clock,
            calendar: TestCalendar(events: [event]),
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.focusDuration = 60
            settings.reminderLead = 60
        }
        let coordinator = fixture.makeCoordinator(historyRecorder: history)
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.calendarStatus == .ready }
        coordinator.startFocus()
        clock.advance(by: 60)
        fixture.postWake()
        try await eventually { coordinator.petState == .reward }

        clock.advance(by: 2)
        fixture.postWake()
        try await eventually { coordinator.petState == .meetingAlert }
        coordinator.dismissMeeting()

        #expect(coordinator.petState == .rest)
        #expect(history.recordCount == 1)
    }

    @Test func successfulLaunchAtLoginToggleCommitsOnlyTheActualServiceState() {
        // Break caught: Settings saves the requested toggle before ServiceManagement reports the real result.
        let now = Date(timeIntervalSinceReferenceDate: 120_000)
        let service = TestLaunchAtLoginService(status: .notRegistered)
        let controller = LaunchAtLoginController(service: service)
        let fixture = makeFixture(
            clock: MutableTestClock(now),
            calendar: TestCalendar(events: []),
            sleepRecorder: SleepRecorder()
        ) { _ in }
        let coordinator = fixture.makeCoordinator(launchAtLoginController: controller)
        defer { fixture.cleanUp(coordinator) }

        #expect(coordinator.launchAtLoginStatus == .notRegistered)
        #expect(!coordinator.settings.launchAtLoginEnabled)

        coordinator.setLaunchAtLoginEnabled(true)

        #expect(service.registerCount == 1)
        #expect(service.unregisterCount == 0)
        #expect(coordinator.launchAtLoginStatus == .enabled)
        #expect(coordinator.launchAtLoginError == nil)
        #expect(fixture.reloadedStore().settings.launchAtLoginEnabled)

        coordinator.setLaunchAtLoginEnabled(false)

        #expect(service.registerCount == 1)
        #expect(service.unregisterCount == 1)
        #expect(coordinator.launchAtLoginStatus == .notRegistered)
        #expect(!fixture.reloadedStore().settings.launchAtLoginEnabled)
    }

    @Test func failedLaunchAtLoginToggleKeepsActualStateAndDoesNotPersistTheRequest() {
        // Break caught: registration failure leaves an optimistic on-state in UserDefaults and hides the error.
        let now = Date(timeIntervalSinceReferenceDate: 130_000)
        let service = TestLaunchAtLoginService(
            status: .notRegistered,
            registerError: TestLaunchAtLoginError.registrationRejected
        )
        let fixture = makeFixture(
            clock: MutableTestClock(now),
            calendar: TestCalendar(events: []),
            sleepRecorder: SleepRecorder()
        ) { _ in }
        let coordinator = fixture.makeCoordinator(
            launchAtLoginController: LaunchAtLoginController(service: service)
        )
        defer { fixture.cleanUp(coordinator) }

        coordinator.setLaunchAtLoginEnabled(true)

        #expect(service.registerCount == 1)
        #expect(coordinator.launchAtLoginStatus == .notRegistered)
        #expect(coordinator.launchAtLoginError != nil)
        #expect(!fixture.reloadedStore().settings.launchAtLoginEnabled)
    }

    @Test func approvalRequiredIsShownAsActualNotEnabledState() {
        // Break caught: a successful register call is displayed and persisted as enabled while macOS still requires approval.
        let now = Date(timeIntervalSinceReferenceDate: 140_000)
        let service = TestLaunchAtLoginService(
            status: .notRegistered,
            statusAfterRegister: .requiresApproval
        )
        let fixture = makeFixture(
            clock: MutableTestClock(now),
            calendar: TestCalendar(events: []),
            sleepRecorder: SleepRecorder()
        ) { _ in }
        let coordinator = fixture.makeCoordinator(
            launchAtLoginController: LaunchAtLoginController(service: service)
        )
        defer { fixture.cleanUp(coordinator) }

        coordinator.setLaunchAtLoginEnabled(true)

        #expect(coordinator.launchAtLoginStatus == .requiresApproval)
        #expect(coordinator.launchAtLoginError == nil)
        #expect(!fixture.reloadedStore().settings.launchAtLoginEnabled)
    }

    @Test func statusRefreshCommitsExternalApprovalWithoutEditingLoginItems() {
        // Break caught: returning from System Settings leaves a stale saved toggle or re-registers without a direct user action.
        let service = TestLaunchAtLoginService(status: .notRegistered)
        let fixture = makeFixture(
            clock: MutableTestClock(Date(timeIntervalSinceReferenceDate: 145_000)),
            calendar: TestCalendar(events: []),
            sleepRecorder: SleepRecorder()
        ) { _ in }
        let coordinator = fixture.makeCoordinator(
            launchAtLoginController: LaunchAtLoginController(service: service)
        )
        defer { fixture.cleanUp(coordinator) }
        service.setStatus(.enabled)

        coordinator.refreshLaunchAtLoginStatus()

        #expect(coordinator.launchAtLoginStatus == .enabled)
        #expect(fixture.reloadedStore().settings.launchAtLoginEnabled)
        #expect(service.registerCount == 0)
        #expect(service.unregisterCount == 0)
    }

    @Test func becomingActiveRefreshesExternalLoginApprovalWithoutEditingLoginItems() async throws {
        // Break caught: approval changed in System Settings stays stale until the Settings window appears again.
        let service = TestLaunchAtLoginService(status: .requiresApproval)
        let fixture = makeFixture(
            clock: MutableTestClock(Date(timeIntervalSinceReferenceDate: 146_000)),
            calendar: TestCalendar(events: []),
            sleepRecorder: SleepRecorder()
        ) { _ in }
        let coordinator = fixture.makeCoordinator(
            launchAtLoginController: LaunchAtLoginController(service: service)
        )
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        #expect(coordinator.launchAtLoginStatus == .requiresApproval)
        #expect(!fixture.reloadedStore().settings.launchAtLoginEnabled)

        service.setStatus(.enabled)
        fixture.applicationNotifications.post(
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        try await eventually { coordinator.launchAtLoginStatus == .enabled }
        #expect(fixture.reloadedStore().settings.launchAtLoginEnabled)
        #expect(service.registerCount == 0)
        #expect(service.unregisterCount == 0)
    }

    @Test func terminationPersistsTheActiveTimerAndStopsOwnedVisualResources() throws {
        // Break caught: quitting loses an active countdown or leaves Dock/panel timers visible after lifecycle teardown.
        let now = Date(timeIntervalSinceReferenceDate: 150_000)
        let tile = TepalTileView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
        let excursion = ExcursionPanelController()
        let fixture = makeFixture(
            clock: MutableTestClock(now),
            calendar: TestCalendar(events: []),
            sleepRecorder: SleepRecorder()
        ) { _ in }
        let coordinator = fixture.makeCoordinator(
            tileView: tile,
            excursionController: excursion,
            reducedMotion: { false }
        )

        coordinator.start()
        coordinator.startFocus()
        excursion.showProbe(
            from: DockGeometry(
                edge: .bottom,
                homePoint: CGPoint(x: 720, y: 48),
                usedPointer: false
            ),
            appearance: coordinator.tepalVisualState,
            onDismiss: {}
        )
        #expect(tile.isAnimating)
        #expect(excursion.isPresented)

        coordinator.terminate()

        #expect(!tile.isAnimating)
        #expect(!excursion.isPresented)
        let recovery = try #require(fixture.reloadedStore().loadTimerRecovery())
        #expect(recovery.snapshot.phase == .focus)
        #expect(recovery.snapshot.remaining == .seconds(1_500))
        #expect(recovery.focusStartDisposition == .interrupted)
        fixture.removeDefaults()
    }

    @Test func terminationBeforeStartStillStopsTheInitialDockAnimation() {
        // Break caught: partial app startup leaves the initial idle animation alive because cleanup is gated on `start()`.
        let tile = TepalTileView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
        let fixture = makeFixture(
            clock: MutableTestClock(Date(timeIntervalSinceReferenceDate: 155_000)),
            calendar: TestCalendar(events: []),
            sleepRecorder: SleepRecorder()
        ) { _ in }
        let coordinator = fixture.makeCoordinator(
            tileView: tile,
            reducedMotion: { false }
        )
        #expect(tile.isAnimating)

        coordinator.terminate()

        #expect(!tile.isAnimating)
        fixture.removeDefaults()
    }

    @Test func authorizationRefreshFinishingAfterTerminationCannotRestartLifecycle() async throws {
        // Break caught: a cancelled refresh resumes after authorization and mutates state, presents a meeting, or restarts rendering/timers.
        try await verifyRefreshFinishingAfterTermination(stage: .authorization)
    }

    @Test func calendarListRefreshFinishingAfterTerminationCannotRestartLifecycle() async throws {
        // Break caught: a cancelled refresh resumes after calendar enumeration and mutates state, presents a meeting, or restarts rendering/timers.
        try await verifyRefreshFinishingAfterTermination(stage: .calendars)
    }

    @Test func eventRefreshFinishingAfterTerminationCannotRestartLifecycle() async throws {
        // Break caught: a cancelled refresh resumes after event fetching and mutates state, presents a meeting, or restarts rendering/timers.
        try await verifyRefreshFinishingAfterTermination(stage: .events)
    }

    @Test func queuedSettingsAndLifecycleNotificationsCannotRearmAfterTermination() async throws {
        // Break caught: observer callbacks queued before teardown run afterward and restart animation or ambient/calendar timers.
        let now = Date(timeIntervalSinceReferenceDate: 157_000)
        let calendar = TestCalendar(events: [])
        let sleepRecorder = SleepRecorder()
        let tile = TepalTileView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
        let excursion = ExcursionPanelController()
        let fixture = makeFixture(
            clock: MutableTestClock(now),
            calendar: calendar,
            sleepRecorder: sleepRecorder
        ) { _ in }
        let coordinator = fixture.makeCoordinator(
            tileView: tile,
            excursionController: excursion,
            reducedMotion: { false }
        )

        coordinator.start()
        try await eventually { coordinator.calendarStatus == .ready }
        try await eventually { await sleepRecorder.invocationCount() > 0 }

        let settingsBeforeQueuedCallback = coordinator.settings
        var queuedSettings = fixture.store.settings
        queuedSettings.petName = "Queued after termination"
        fixture.store.settings = queuedSettings
        fixture.applicationNotifications.post(
            name: SettingsStore.settingsDidChangeNotification,
            object: fixture.store
        )
        fixture.workspaceNotifications.post(name: NSWorkspace.didWakeNotification, object: nil)
        fixture.applicationNotifications.post(name: .NSSystemClockDidChange, object: nil)
        coordinator.terminate()
        let sleepCountAfterTermination = await sleepRecorder.invocationCount()

        await settle()

        #expect(coordinator.settings == settingsBeforeQueuedCallback)
        #expect(!tile.isAnimating)
        #expect(!excursion.isPresented)
        #expect(await sleepRecorder.invocationCount() == sleepCountAfterTermination)
        fixture.removeDefaults()
    }

    @Test func missingSemanticRendererLeavesTimerAndCalendarCoordinationOperational() async throws {
        // Break caught: pixel-renderer initialization failure prevents Pomodoro and Calendar state from starting.
        let now = Date(timeIntervalSinceReferenceDate: 160_000)
        let fixture = makeFixture(
            clock: MutableTestClock(now),
            calendar: TestCalendar(events: []),
            sleepRecorder: SleepRecorder()
        ) { _ in }
        let coordinator = fixture.makeCoordinator(tileView: nil)
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        coordinator.startFocus()
        try await eventually { coordinator.calendarStatus == .ready }

        #expect(coordinator.pomodoro.phase == .focus)
        #expect(!coordinator.pomodoro.isPaused)
        #expect(coordinator.calendarStatus == .ready)
    }

    @Test func ambientSleepDoesNotKeepTheCoordinatorAliveWithoutAnOwner() async {
        // Break caught: `while let self` retains the entire coordinator for a 30-minute ambient sleep.
        let now = Date(timeIntervalSinceReferenceDate: 170_000)
        let fixture = makeFixture(
            clock: MutableTestClock(now),
            calendar: TestCalendar(events: []),
            sleepRecorder: SleepRecorder()
        ) { _ in }
        weak var releasedCoordinator: AppCoordinator?

        do {
            let coordinator = fixture.makeCoordinator()
            releasedCoordinator = coordinator
            coordinator.start()
            await settle()
        }
        await settle()

        #expect(releasedCoordinator == nil)
        fixture.removeDefaults()
    }

    @Test func completeLocalDataResetClearsTimerReminderSettingsAndRuntimeCalendarState() async throws {
        // Break caught: the Settings clear action removes history but leaves recovery, reminder keys, calendar selections, or event content behind.
        let now = Date(timeIntervalSinceReferenceDate: 180_000)
        let event = meeting(id: "private-event", start: now.addingTimeInterval(900))
        let fixture = makeFixture(
            clock: MutableTestClock(now),
            calendar: TestCalendar(events: [event]),
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.petName = "Pip"
            settings.soundEnabled = true
        }
        fixture.store.saveReminderState(ReminderState(
            shown: [ReminderOccurrenceKey(eventID: event.id, start: event.start)],
            snoozedUntil: [:],
            snoozeUsed: []
        ))
        let coordinator = fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.calendarStatus == .ready }
        coordinator.startFocus()
        fixture.store.saveTimerRecovery(PomodoroRecovery(
            snapshot: coordinator.pomodoro,
            focusStartDisposition: .interrupted
        ))
        #expect(fixture.reloadedStore().loadTimerRecovery() != nil)

        coordinator.clearAllLocalData()

        let reloaded = fixture.reloadedStore()
        #expect(reloaded.settings == .defaults)
        #expect(reloaded.loadTimerRecovery() == nil)
        #expect(reloaded.loadReminderState() == ReminderState())
        #expect(coordinator.settings == .defaults)
        #expect(coordinator.pomodoro.phase == .idle)
        #expect(coordinator.nextEvent == nil)
        #expect(coordinator.calendarStatus == .notRequested)
    }

    @Test func unavailableHistoryRecoversWhileDefaultsAndRuntimeClearIndependently() async throws {
        // Break caught: a failed initial HistoryStore construction disables the complete local-data clear action.
        let now = Date(timeIntervalSinceReferenceDate: 181_000)
        let event = meeting(id: "private-before-history-recovery", start: now.addingTimeInterval(900))
        let service = TestLaunchAtLoginService(status: .enabled)
        let fixture = makeFixture(
            clock: MutableTestClock(now),
            calendar: TestCalendar(events: [event]),
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.petName = "Private pet name"
            settings.soundEnabled = true
        }
        fixture.store.saveReminderState(ReminderState(
            shown: [ReminderOccurrenceKey(eventID: event.id, start: event.start)],
            snoozedUntil: [:],
            snoozeUsed: []
        ))
        let history = HistoryStoreController(
            makeStore: { throw HistoryResetTestError.initializationFailed },
            recoverStore: { try makeInMemoryHistoryStore() }
        )
        let coordinator = fixture.makeCoordinator(
            historyRecorder: history,
            launchAtLoginController: LaunchAtLoginController(service: service)
        )
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { coordinator.calendarStatus == .ready }
        coordinator.startFocus()
        fixture.store.saveTimerRecovery(PomodoroRecovery(
            snapshot: coordinator.pomodoro,
            focusStartDisposition: .interrupted
        ))
        #expect(history.store == nil)

        let result = LocalDataClearer.clear(
            coordinator: coordinator,
            historyStoreController: history
        )

        #expect(result == .complete(historyRecovered: true))
        #expect(history.store != nil)
        #expect(try history.store?.completedFocusCount() == 0)
        let reloaded = fixture.reloadedStore()
        #expect(reloaded.settings == .defaults)
        #expect(reloaded.loadTimerRecovery() == nil)
        #expect(reloaded.loadReminderState() == ReminderState())
        #expect(coordinator.pomodoro.phase == .idle)
        #expect(coordinator.nextEvent == nil)
        #expect(service.registerCount == 0)
        #expect(service.unregisterCount == 0)
    }

    @Test func failedHistoryResetReportsPartialFailureAfterDefaultsStillClear() throws {
        // Break caught: a history save/reset failure falsely reports that no settings were removed and aborts runtime clearing.
        let fixture = makeFixture(
            clock: MutableTestClock(Date(timeIntervalSinceReferenceDate: 182_000)),
            calendar: TestCalendar(events: []),
            sleepRecorder: SleepRecorder()
        ) { settings in
            settings.petName = "Must be cleared"
            settings.onboardingCompleted = true
        }
        let service = TestLaunchAtLoginService(status: .notRegistered)
        let failingStore = try makeInMemoryHistoryStore(failingSaves: true)
        let history = HistoryStoreController(
            makeStore: { failingStore },
            recoverStore: { throw HistoryResetTestError.recoveryFailed }
        )
        let coordinator = fixture.makeCoordinator(
            historyRecorder: history,
            launchAtLoginController: LaunchAtLoginController(service: service)
        )
        defer { fixture.cleanUp(coordinator) }
        coordinator.startFocus()

        let result = LocalDataClearer.clear(
            coordinator: coordinator,
            historyStoreController: history
        )

        #expect(result == .partialHistoryFailure)
        #expect(history.store == nil)
        #expect(fixture.reloadedStore().settings == .defaults)
        #expect(fixture.reloadedStore().loadTimerRecovery() == nil)
        #expect(fixture.reloadedStore().loadReminderState() == ReminderState())
        #expect(coordinator.settings == .defaults)
        #expect(coordinator.pomodoro.phase == .idle)
        #expect(service.registerCount == 0)
        #expect(service.unregisterCount == 0)
    }

    @Test func clearAllLocalDataRejectsAStaleSuspendedEventResultAndAllowsALaterRefresh() async throws {
        // Break caught: an event fetch started before clearing local data repopulates private summaries, reminder keys, and the meeting panel afterward.
        let now = Date(timeIntervalSinceReferenceDate: 185_000)
        let staleEvent = meeting(id: "stale-private-event", start: now.addingTimeInterval(60))
        let legitimateEvent = meeting(id: "later-legitimate-event", start: now.addingTimeInterval(900))
        let calendar = SuspendedTestCalendar(stage: .events, events: [staleEvent])
        let excursion = ExcursionPanelController()
        let fixture = makeFixture(
            clock: MutableTestClock(now),
            calendar: calendar,
            sleepRecorder: SleepRecorder()
        ) { _ in }
        let coordinator = fixture.makeCoordinator(excursionController: excursion)
        defer { fixture.cleanUp(coordinator) }

        coordinator.start()
        try await eventually { await calendar.isSuspended }

        coordinator.clearAllLocalData()

        #expect(coordinator.nextEvent == nil)
        #expect(coordinator.calendarChoices.isEmpty)
        #expect(coordinator.calendarStatus == .notRequested)
        #expect(fixture.reloadedStore().loadReminderState() == ReminderState())
        #expect(!excursion.isPresented)

        await calendar.setEvents([legitimateEvent])
        var restoredSettings = coordinator.settings
        restoredSettings.confirmedGoogleSourceIDs = ["google-source"]
        restoredSettings.enabledCalendarIDs = ["work"]
        coordinator.saveSettings(restoredSettings)
        coordinator.settingsDidChange()

        try await eventually {
            coordinator.calendarStatus == .ready && coordinator.nextEvent == legitimateEvent
        }

        await calendar.resume()
        await settle()

        #expect(coordinator.calendarStatus == .ready)
        #expect(coordinator.nextEvent == legitimateEvent)
        #expect(fixture.reloadedStore().loadReminderState() == ReminderState())
        #expect(!excursion.isPresented)
    }

    private func verifyRefreshFinishingAfterTermination(
        stage: CalendarRefreshSuspensionStage
    ) async throws {
        let now = Date(timeIntervalSinceReferenceDate: 156_000)
        let staleEvent = meeting(id: "post-termination-event", start: now.addingTimeInterval(60))
        let calendar = SuspendedTestCalendar(
            stage: stage,
            events: [staleEvent],
            authorization: stage == .authorization ? .denied : .fullAccess
        )
        let sleepRecorder = SleepRecorder()
        let tile = TepalTileView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
        let excursion = ExcursionPanelController()
        let fixture = makeFixture(
            clock: MutableTestClock(now),
            calendar: calendar,
            sleepRecorder: sleepRecorder
        ) { _ in }
        let coordinator = fixture.makeCoordinator(
            tileView: tile,
            excursionController: excursion,
            reducedMotion: { false }
        )

        coordinator.start()
        try await eventually { await calendar.isSuspended }
        coordinator.terminate()

        let statusAfterTermination = coordinator.calendarStatus
        let choicesAfterTermination = coordinator.calendarChoices
        let petStateAfterTermination = coordinator.petState
        let sleepCountAfterTermination = await sleepRecorder.invocationCount()
        #expect(!tile.isAnimating)
        #expect(!excursion.isPresented)

        await calendar.resume()
        await settle()

        #expect(coordinator.calendarStatus == statusAfterTermination)
        #expect(coordinator.calendarChoices == choicesAfterTermination)
        #expect(coordinator.nextEvent == nil)
        #expect(coordinator.petState == petStateAfterTermination)
        #expect(!tile.isAnimating)
        #expect(!excursion.isPresented)
        #expect(await sleepRecorder.invocationCount() == sleepCountAfterTermination)
        fixture.removeDefaults()
    }
}

@MainActor
private struct CoordinatorFixture {
    let store: SettingsStore
    let defaults: UserDefaults
    let suiteName: String
    let clock: MutableTestClock
    let calendar: any CalendarReading
    let sleepRecorder: SleepRecorder
    let workspaceNotifications: NotificationCenter
    let applicationNotifications: NotificationCenter

    func makeCoordinator(
        historyRecorder: (any FocusHistoryRecording)? = nil,
        settingsStore: SettingsStore? = nil,
        launchAtLoginController: LaunchAtLoginController = LaunchAtLoginController(),
        soundPlayer: any LocalSoundPlaying = SilentLocalSoundPlayer(),
        tileView: TepalTileView? = TepalTileView(
            frame: NSRect(x: 0, y: 0, width: 128, height: 128)
        ),
        excursionController: any ExcursionPresenting = ExcursionPanelController(),
        reducedMotion: @escaping @MainActor () -> Bool = { true },
        ensureControlPanelPresented: @escaping @MainActor (DockGeometry) -> Void = { _ in }
    ) -> AppCoordinator {
        AppCoordinator(
            settingsStore: settingsStore ?? store,
            historyStore: historyRecorder,
            launchAtLoginController: launchAtLoginController,
            soundPlayer: soundPlayer,
            calendar: calendar,
            clock: clock,
            tileView: tileView,
            excursionController: excursionController,
            sleep: { interval in try await sleepRecorder.sleep(interval) },
            randomJitter: { 0 },
            screenGeometries: {
                [ScreenGeometry(
                    frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
                    visibleFrame: CGRect(x: 0, y: 48, width: 1_440, height: 852)
                )]
            },
            pointerLocation: { .zero },
            reducedMotion: reducedMotion,
            ensureControlPanelPresented: ensureControlPanelPresented,
            workspaceNotifications: workspaceNotifications,
            applicationNotifications: applicationNotifications,
            processArguments: []
        )
    }

    func postWake() {
        workspaceNotifications.post(name: NSWorkspace.didWakeNotification, object: nil)
    }

    func reloadedStore() -> SettingsStore {
        SettingsStore(userDefaults: defaults)
    }

    func saveLegacyRecovery(_ snapshot: PomodoroSnapshot) throws {
        let record = LegacyTimerRecoveryRecord(version: 1, value: snapshot)
        defaults.set(
            try JSONEncoder().encode(record),
            forKey: "dockpet.v1.recovery"
        )
    }

    func cleanUp(_ coordinator: AppCoordinator) {
        coordinator.terminate()
        removeDefaults()
    }

    func removeDefaults() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
private final class TestLaunchAtLoginService: LaunchAtLoginServicing {
    private(set) var status: SMAppService.Status
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private let statusAfterRegister: SMAppService.Status
    private let registerError: (any Error)?

    init(
        status: SMAppService.Status,
        statusAfterRegister: SMAppService.Status = .enabled,
        registerError: (any Error)? = nil
    ) {
        self.status = status
        self.statusAfterRegister = statusAfterRegister
        self.registerError = registerError
    }

    func register() throws {
        registerCount += 1
        if let registerError { throw registerError }
        status = statusAfterRegister
    }

    func unregister() throws {
        unregisterCount += 1
        status = .notRegistered
    }

    func setStatus(_ status: SMAppService.Status) {
        self.status = status
    }
}

private enum TestLaunchAtLoginError: Error {
    case registrationRejected
}

@MainActor
private final class PanelPresentationRecorder {
    private(set) var isPresented = false
    private(set) var ensureCount = 0

    func ensurePresented() {
        isPresented = true
        ensureCount += 1
    }
}

@MainActor
private func makeFixture(
    clock: MutableTestClock,
    calendar: any CalendarReading,
    sleepRecorder: SleepRecorder,
    configure: (inout AppSettings) -> Void
) -> CoordinatorFixture {
    let suiteName = "Tepal.AppCoordinatorReminderTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let store = SettingsStore(userDefaults: defaults)
    var settings = AppSettings.defaults
    settings.enabledCalendarIDs = ["work"]
    settings.confirmedGoogleSourceIDs = ["google-source"]
    configure(&settings)
    store.settings = settings
    return CoordinatorFixture(
        store: store,
        defaults: defaults,
        suiteName: suiteName,
        clock: clock,
        calendar: calendar,
        sleepRecorder: sleepRecorder,
        workspaceNotifications: NotificationCenter(),
        applicationNotifications: NotificationCenter()
    )
}

private struct LegacyTimerRecoveryRecord: Codable {
    let version: Int
    let value: PomodoroSnapshot
}

@MainActor
private final class FakeHistoryRecorder: FocusHistoryRecording {
    private(set) var recordCount = 0
    private(set) var operations: [String] = []
    private var completedFocuses: Int
    private let rewardsOnRecord: [CosmeticReward]
    private var existingRewardIDs: Set<CosmeticReward>
    private var recordsThrow = false
    private var snapshotReadsThrow = false

    init(
        completedFocuses: Int = 0,
        rewardsOnRecord: [CosmeticReward] = [.glow],
        existingRewardIDs: Set<CosmeticReward> = []
    ) {
        self.completedFocuses = completedFocuses
        self.rewardsOnRecord = rewardsOnRecord
        self.existingRewardIDs = existingRewardIDs
    }

    func recordCompletedFocus(endedAt: Date, duration: TimeInterval?) throws -> [RewardSummary] {
        operations.append("record")
        if recordsThrow { throw FakeHistoryRecorderError.unavailable }
        recordCount += 1
        completedFocuses += 1
        existingRewardIDs.formUnion(rewardsOnRecord)
        return rewardsOnRecord.map { RewardSummary(reward: $0, unlockedAt: endedAt) }
    }

    func focusHistorySnapshot() throws -> FocusHistorySnapshot {
        operations.append("snapshot")
        if snapshotReadsThrow { throw FakeHistoryRecorderError.unavailable }
        return FocusHistorySnapshot(
            completedFocusCount: completedFocuses,
            rewardIDs: existingRewardIDs
        )
    }

    func failFutureRecords() {
        recordsThrow = true
    }

    func failFutureSnapshotReads() {
        snapshotReadsThrow = true
    }
}

private enum FakeHistoryRecorderError: Error {
    case unavailable
}

private final class MutableTestClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ now: Date) {
        current = now
    }

    var now: Date {
        lock.withLock { current }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(interval) }
    }
}

@MainActor
private final class SoundRecorder: LocalSoundPlaying {
    private(set) var cues: [LocalSoundCue] = []

    func play(_ cue: LocalSoundCue) {
        cues.append(cue)
    }
}

@MainActor
private final class PersistenceInspectingExcursion: ExcursionPresenting {
    var isPresented = false
    var presentedTitles: [String] = []
    var presentationCount = 0
    var shownAtPresentation: Set<ReminderOccurrenceKey> = []
    var presentedAppearance: TepalVisualState?
    var probeAppearance: TepalVisualState?
    var onMeetingPresentation: () -> Void = {}

    func showProbe(
        from geometry: DockGeometry,
        appearance: TepalVisualState,
        onDismiss: @escaping () -> Void
    ) {
        isPresented = true
        probeAppearance = appearance
    }

    func showMeetings(
        titles: [String],
        start: Date,
        from home: DockGeometry,
        appearance: TepalVisualState,
        onDismiss: @escaping () -> Void,
        onSnooze: @escaping () -> Void
    ) {
        isPresented = true
        presentedTitles = titles
        presentedAppearance = appearance
        presentationCount += 1
        onMeetingPresentation()
    }

    func showMeetingsWithoutSnooze(
        titles: [String],
        start: Date,
        from home: DockGeometry,
        appearance: TepalVisualState,
        onDismiss: @escaping () -> Void
    ) {
        isPresented = true
        presentedTitles = titles
        presentedAppearance = appearance
        presentationCount += 1
        onMeetingPresentation()
    }

    func hide() {
        isPresented = false
        presentedTitles = []
        presentedAppearance = nil
        probeAppearance = nil
    }
}

private actor TestCalendar: CalendarReading {
    private var eventValues: [CalendarEventSummary]
    private var calendarValues: [CalendarDescriptor]
    private var authorization: CalendarAuthorizationStatus
    private var authorizationReads = 0
    private var requests = 0
    private var eventReads = 0
    private var requestedCalendarIDs: Set<String> = []
    private var suspendNextEventRead = false
    private var eventReadContinuation: CheckedContinuation<Void, Never>?
    private let requestError: (any Error)?

    init(
        events: [CalendarEventSummary],
        calendars: [CalendarDescriptor] = [
            CalendarDescriptor(
                id: "work",
                title: "Work",
                sourceTitle: "Google",
                sourceID: "google-source",
                sourceEligibility: .requiresGoogleConfirmation
            )
        ],
        authorization: CalendarAuthorizationStatus = .fullAccess,
        requestError: (any Error)? = nil
    ) {
        eventValues = events
        calendarValues = calendars
        self.authorization = authorization
        self.requestError = requestError
    }

    func authorizationStatus() async -> CalendarAuthorizationStatus {
        authorizationReads += 1
        return authorization
    }

    func requestFullAccess() async throws -> Bool {
        requests += 1
        if let requestError { throw requestError }
        let granted = authorization == .fullAccess
        if authorization == .notDetermined, !granted {
            authorization = .denied
        }
        return granted
    }

    func calendars() async throws -> [CalendarDescriptor] {
        calendarValues
    }

    func events(
        from: Date,
        through: Date,
        calendarIDs: Set<String>
    ) async throws -> [CalendarEventSummary] {
        eventReads += 1
        requestedCalendarIDs = calendarIDs
        let result = eventValues
        if suspendNextEventRead {
            suspendNextEventRead = false
            await withCheckedContinuation { continuation in
                eventReadContinuation = continuation
            }
        }
        return result
    }

    func setAuthorization(_ authorization: CalendarAuthorizationStatus) {
        self.authorization = authorization
    }

    func setEvents(_ events: [CalendarEventSummary]) {
        eventValues = events
    }

    func suspendNextEventFetch() {
        suspendNextEventRead = true
    }

    var isEventFetchSuspended: Bool {
        eventReadContinuation != nil
    }

    func resumeEventFetch() {
        eventReadContinuation?.resume()
        eventReadContinuation = nil
    }

    func authorizationReadCount() -> Int { authorizationReads }
    func requestCount() -> Int { requests }
    func eventReadCount() -> Int { eventReads }
    func lastRequestedCalendarIDs() -> Set<String> { requestedCalendarIDs }

    nonisolated func changes() -> AsyncStream<Void> {
        AsyncStream { _ in }
    }
}

private enum TestCalendarError: Error {
    case requestFailed
}

private enum HistoryResetTestError: Error {
    case initializationFailed
    case recoveryFailed
    case forcedSaveFailure
}

@MainActor
private func makeInMemoryHistoryStore(failingSaves: Bool = false) throws -> HistoryStore {
    let schema = Schema([FocusSessionRecord.self, UnlockedRewardRecord.self])
    let configuration = ModelConfiguration(
        "TepalAppHistoryTests-\(UUID().uuidString)",
        schema: schema,
        isStoredInMemoryOnly: true,
        groupContainer: .none,
        cloudKitDatabase: .none
    )
    let container = try ModelContainer(
        for: FocusSessionRecord.self,
        UnlockedRewardRecord.self,
        configurations: configuration
    )
    if failingSaves {
        return HistoryStore(modelContainer: container, saveContext: { _ in
            throw HistoryResetTestError.forcedSaveFailure
        })
    }
    return HistoryStore(modelContainer: container)
}

private enum CalendarRefreshSuspensionStage: Sendable {
    case authorization
    case calendars
    case events
}

private actor SuspendedTestCalendar: CalendarReading {
    private let stage: CalendarRefreshSuspensionStage
    private var eventValues: [CalendarEventSummary]
    private let authorization: CalendarAuthorizationStatus
    private var continuation: CheckedContinuation<Void, Never>?
    private var didSuspend = false

    init(
        stage: CalendarRefreshSuspensionStage,
        events: [CalendarEventSummary],
        authorization: CalendarAuthorizationStatus = .fullAccess
    ) {
        self.stage = stage
        eventValues = events
        self.authorization = authorization
    }

    var isSuspended: Bool {
        continuation != nil
    }

    func authorizationStatus() async -> CalendarAuthorizationStatus {
        await suspendIfNeeded(at: .authorization)
        return authorization
    }

    func requestFullAccess() async throws -> Bool {
        true
    }

    func calendars() async throws -> [CalendarDescriptor] {
        await suspendIfNeeded(at: .calendars)
        return [CalendarDescriptor(
            id: "work",
            title: "Work",
            sourceTitle: "Google",
            sourceID: "google-source",
            sourceEligibility: .requiresGoogleConfirmation
        )]
    }

    func events(
        from: Date,
        through: Date,
        calendarIDs: Set<String>
    ) async throws -> [CalendarEventSummary] {
        let result = eventValues
        await suspendIfNeeded(at: .events)
        return result
    }

    nonisolated func changes() -> AsyncStream<Void> {
        AsyncStream { _ in }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }

    func setEvents(_ events: [CalendarEventSummary]) {
        eventValues = events
    }

    private func suspendIfNeeded(at currentStage: CalendarRefreshSuspensionStage) async {
        guard currentStage == stage, !didSuspend else { return }
        didSuspend = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }
}

private actor SleepRecorder {
    private var intervals: [TimeInterval] = []

    func sleep(_ interval: TimeInterval) async throws {
        intervals.append(interval)
        try await Task.sleep(for: .seconds(3_600))
    }

    func shortIntervals() -> [TimeInterval] {
        intervals.filter { $0 < AppSettings.defaults.minimumAmbientInterval }
    }

    func invocationCount() -> Int {
        intervals.count
    }
}

private func meeting(id: String, start: Date) -> CalendarEventSummary {
    CalendarEventSummary(
        id: id,
        title: id.capitalized,
        start: start,
        end: start.addingTimeInterval(600),
        calendarID: "work",
        isAllDay: false,
        isCancelled: false
    )
}

@MainActor
private func eventually(
    _ predicate: @escaping @MainActor () async -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    for _ in 0 ..< 200 {
        if await predicate() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Condition was not met before timeout", sourceLocation: sourceLocation)
}

private func settle() async {
    for _ in 0 ..< 20 {
        await Task.yield()
    }
}
