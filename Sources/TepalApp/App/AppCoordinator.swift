import AppKit
import TepalCore
import TepalMac
import Foundation
import Observation
import ServiceManagement
#if DEBUG
import OSLog
#endif

public enum CalendarStatus: Equatable, Sendable {
    case notRequested
    case refreshing
    case disconnected
    case noSelection
    case ready
    case accessDenied
    case unavailable(message: String)
}

@MainActor
public protocol FocusHistoryRecording: AnyObject {
    func recordCompletedFocus(endedAt: Date, duration: TimeInterval?) throws -> [RewardSummary]
    func focusHistorySnapshot() throws -> FocusHistorySnapshot
}

extension HistoryStore: FocusHistoryRecording {}

@MainActor
@Observable
public final class AppCoordinator {
    public private(set) var pomodoro: PomodoroSnapshot
    public private(set) var petState: PetState
    public private(set) var nextEvent: CalendarEventSummary?
    public private(set) var calendarStatus: CalendarStatus = .notRequested
    public private(set) var focusOverlap: CalendarEventSummary?
    public private(set) var calendarChoices: [CalendarDescriptor] = []
    public private(set) var settings: AppSettings
    public private(set) var launchAtLoginStatus: SMAppService.Status
    public private(set) var launchAtLoginError: String?
    public private(set) var tepalCompletedFocusCount: Int
    public private(set) var historySaveError: String?
    public private(set) var pendingTepalUnlock: TepalPaletteID?

    public var tepalVisualState: TepalVisualState {
        let profile = TepalGrowthProfile(completedFocuses: tepalCompletedFocusCount)
        let effectivePalette = profile.availablePalettes.contains(settings.tepalPalette)
            ? settings.tepalPalette
            : .moonFern
        return TepalPresentationPolicy.make(
            petState: petState,
            isTimerPaused: pomodoro.isPaused,
            timerProgress: timerProgress,
            palette: effectivePalette,
            completedFocuses: tepalCompletedFocusCount,
            reducedMotion: effectiveReducedMotion
        )
    }

    private struct MeetingOccurrence: Equatable {
        let event: CalendarEventSummary
        let key: ReminderOccurrenceKey
    }

    private struct ActiveMeeting {
        var occurrences: [MeetingOccurrence]

        var earliestStart: Date {
            occurrences.map(\.event.start).min() ?? .distantFuture
        }

        var titles: [String] {
            occurrences.map(\.event.title)
        }
    }

    private enum FocusStartPauseReason {
        case overlapConfirmation
        case wakeAutoStartAwaitingCalendar
    }

    private enum FocusTransitionContext {
        case ordinary
        case wakeBeforeCalendarRefresh
    }

    public typealias Sleep = @Sendable (TimeInterval) async throws -> Void

    private let settingsStore: SettingsStore
    private let historyStore: (any FocusHistoryRecording)?
    private let launchAtLoginController: LaunchAtLoginController
    private let soundPlayer: any LocalSoundPlaying
    private let calendar: any CalendarReading
    private let clock: any Clock
    private let activityMonitor: any UserActivityReading
    private let tileView: TepalTileView?
    private let excursionController: any ExcursionPresenting
    private let sleep: Sleep
    private let randomJitter: @Sendable () -> TimeInterval
    private let screenGeometries: @MainActor () -> [ScreenGeometry]
    private let pointerLocation: @MainActor () -> CGPoint
    private let reducedMotion: @MainActor () -> Bool
    private let toggleControlPanel: @MainActor (DockGeometry) -> Void
    private let ensureControlPanelPresented: @MainActor (DockGeometry) -> Void
    private let workspaceNotifications: NotificationCenter
    private let applicationNotifications: NotificationCenter

    private var engine: PomodoroEngine
    private var petMachine: PetStateMachine
    private var events: [CalendarEventSummary] = []
    private var reminderState: ReminderState
    private var activeMeeting: ActiveMeeting?
    private var dockHome: DockGeometry?
    private var focusStartPauseReason: FocusStartPauseReason?
    private var pendingRewardReaction = false
    private var rewardReactionIsActive = false
    private var rewardReactionEnd: Date?
    private var pausedRewardReactionRemaining: TimeInterval?
    private var queuedTepalUnlock: TepalPaletteID?
    private var started = false
    private var calendarRefreshEpoch: UInt = 0

    private let refreshStream: AsyncStream<Void>
    private let refreshContinuation: AsyncStream<Void>.Continuation
    private var timerTask: Task<Void, Never>?
    private var refreshLoopTask: Task<Void, Never>?
    private var calendarRefreshTask: Task<Void, Never>?
    private var calendarRefreshRequiredBeforeReminders = false
    private var changeConsumerTask: Task<Void, Never>?
    private var ambientTask: Task<Void, Never>?
    private var calendarRefreshTimer: Timer?
    private var notificationObservers: [NSObjectProtocol] = []

    #if DEBUG
    private let demoMeeting: CalendarEventSummary?
    private static let demoLogger = Logger(subsystem: "com.or-balog.tepal", category: "DemoMeeting")
    #endif

    public init(
        settingsStore: SettingsStore = SettingsStore(),
        historyStore: (any FocusHistoryRecording)? = nil,
        launchAtLoginController: LaunchAtLoginController = LaunchAtLoginController(),
        soundPlayer: any LocalSoundPlaying = AppKitLocalSoundPlayer(),
        calendar: any CalendarReading = EventKitCalendarReader(),
        clock: any Clock = SystemClock(),
        activityMonitor: any UserActivityReading = SystemUserActivityMonitor(),
        tileView: TepalTileView?,
        excursionController: any ExcursionPresenting,
        sleep: @escaping Sleep = { interval in
            try await Task.sleep(for: .seconds(max(0, interval)))
        },
        randomJitter: @escaping @Sendable () -> TimeInterval = {
            Double.random(in: 0 ... 300)
        },
        screenGeometries: @escaping @MainActor () -> [ScreenGeometry] = {
            NSScreen.screens.map { ScreenGeometry(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        },
        pointerLocation: @escaping @MainActor () -> CGPoint = {
            NSEvent.mouseLocation
        },
        reducedMotion: @escaping @MainActor () -> Bool = {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        },
        toggleControlPanel: @escaping @MainActor (DockGeometry) -> Void = { _ in },
        ensureControlPanelPresented: @escaping @MainActor (DockGeometry) -> Void = { _ in },
        workspaceNotifications: NotificationCenter = NSWorkspace.shared.notificationCenter,
        applicationNotifications: NotificationCenter = .default,
        processArguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        self.settingsStore = settingsStore
        self.historyStore = historyStore
        self.launchAtLoginController = launchAtLoginController
        self.soundPlayer = soundPlayer
        self.calendar = calendar
        self.clock = clock
        self.activityMonitor = activityMonitor
        self.tileView = tileView
        self.excursionController = excursionController
        self.sleep = sleep
        self.randomJitter = randomJitter
        self.screenGeometries = screenGeometries
        self.pointerLocation = pointerLocation
        self.reducedMotion = reducedMotion
        self.toggleControlPanel = toggleControlPanel
        self.ensureControlPanelPresented = ensureControlPanelPresented
        self.workspaceNotifications = workspaceNotifications
        self.applicationNotifications = applicationNotifications

        let loadedSettings = settingsStore.settings
        let loadedReminderState = settingsStore.loadReminderState()
        let loadedRecovery = settingsStore.loadTimerRecovery()
        let now = clock.now
        let initialEngine: PomodoroEngine
        let initialPomodoro: PomodoroSnapshot
        if let recovered = loadedRecovery?.snapshot,
           let recoveredEngine = PomodoroEngine(
               recovering: recovered,
               settings: loadedSettings
           )
        {
            initialEngine = recoveredEngine
            initialPomodoro = recovered
        } else {
            var newEngine = PomodoroEngine(settings: loadedSettings)
            initialPomodoro = newEngine.send(.tick, at: now)
            initialEngine = newEngine
        }

        var newPetMachine = PetStateMachine()
        let initialPetState = newPetMachine.send(.timerPhase(initialPomodoro.phase))

        settings = loadedSettings
        launchAtLoginStatus = launchAtLoginController.status
        launchAtLoginError = nil
        tepalCompletedFocusCount = (
            try? historyStore?.focusHistorySnapshot().tepalEffectiveCompletedFocusCount
        ) ?? 0
        pendingTepalUnlock = nil
        queuedTepalUnlock = nil
        reminderState = loadedReminderState
        engine = initialEngine
        pomodoro = initialPomodoro
        petState = initialPetState
        petMachine = newPetMachine
        focusStartPauseReason = initialPomodoro.phase == .focus
            && initialPomodoro.isPaused
            && loadedRecovery?.focusStartDisposition.requiresOverlapConfirmation == true
            ? .overlapConfirmation
            : nil

        let refreshPair = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        refreshStream = refreshPair.stream
        refreshContinuation = refreshPair.continuation

        #if DEBUG
        if let delay = Self.demoMeetingDelay(in: processArguments) {
            let alertAt = now.addingTimeInterval(delay)
            let start = alertAt.addingTimeInterval(loadedSettings.reminderLead)
            demoMeeting = CalendarEventSummary(
                id: "tepal-debug-demo-meeting",
                title: "Demo Meeting",
                start: start,
                end: start.addingTimeInterval(1_800),
                calendarID: "tepal-debug",
                isAllDay: false,
                isCancelled: false
            )
            Self.reportDemo("scheduled local alert in \(delay) seconds")
        } else {
            demoMeeting = nil
        }
        #endif

        renderDock()
    }

    @ObservationIgnored private(set) lazy var knockCalendar = KnockCalendarController(calendar: calendar, visual: { [weak self] in
        self?.tepalVisualState ?? TepalVisualState(pose: .ready, timerProgress: 0, palette: .moonFern,
            growth: TepalGrowthProfile(completedFocuses: 0), reducedMotion: true)
    })

    public func start() {
        guard !started else { return }
        started = true

        installLifecycleObservers()
        knockCalendar.configure(settings)
        startRefreshLoop()
        startCalendarChangeConsumer()
        restartCalendarRefreshTimer()
        restartAmbientTask()

        updateTimer(at: clock.now, evaluateReminders: false)
        refreshCalendar()
        rescheduleTimerTask()
    }

    public func terminate() {
        knockCalendar.stop()
        started = false
        invalidateCalendarRefresh()

        timerTask?.cancel()
        refreshLoopTask?.cancel()
        calendarRefreshTask?.cancel()
        changeConsumerTask?.cancel()
        ambientTask?.cancel()
        timerTask = nil
        refreshLoopTask = nil
        calendarRefreshTask = nil
        calendarRefreshRequiredBeforeReminders = false
        changeConsumerTask = nil
        ambientTask = nil
        refreshContinuation.finish()

        calendarRefreshTimer?.invalidate()
        calendarRefreshTimer = nil
        pendingRewardReaction = false
        rewardReactionIsActive = false
        rewardReactionEnd = nil
        pausedRewardReactionRemaining = nil
        queuedTepalUnlock = nil

        for observer in notificationObservers {
            workspaceNotifications.removeObserver(observer)
            applicationNotifications.removeObserver(observer)
        }
        notificationObservers.removeAll()

        excursionController.hide()
        tileView?.stopAnimation()
        persistCurrentState()
    }

    private var pendingPreparationEvent: CalendarEventSummary?

    public var meetingFocusCandidate: CalendarEventSummary? {
        guard pomodoro.phase == .idle, calendarStatus == .ready,
              !calendarRefreshRequiredBeforeReminders else { return nil }
        let now = clock.now
        guard let event = events.first(where: { !$0.isAllDay && !$0.isCancelled && $0.start > now }),
              event.start.timeIntervalSince(now) >= 180 else { return nil }
        // Do not offer a focus session during another meeting already in progress.
        guard !events.contains(where: { !$0.isAllDay && !$0.isCancelled && $0.start <= now && $0.end > now }) else { return nil }
        return event
    }

    public func startFocusUntilNextMeeting() {
        guard let event = meetingFocusCandidate else { return }
        send(.startFocusUntilMeeting(event), bypassingFocusOverlap: true)
    }

    private func presentPreparationIfNeeded(from previous: PomodoroSnapshot, at now: Date) {
        if let selected = previous.meetingFocusEvent,
           pomodoro.meetingFocusEvent == nil,
           now >= selected.start.addingTimeInterval(-120), now < selected.start {
            pendingPreparationEvent = selected
        }
        deliverPendingPreparation(at: now)
    }

    private func deliverPendingPreparation(at now: Date) {
        guard let selected = pendingPreparationEvent,
              !calendarRefreshRequiredBeforeReminders, calendarStatus == .ready else { return }
        pendingPreparationEvent = nil
        guard now < selected.start,
              let event = events.first(where: { $0.id == selected.id && $0.start == selected.start && !$0.isCancelled }) else { return }
        let key = ReminderOccurrenceKey(eventID: event.id, start: event.start)
        reminderState.shown.insert(key)
        reminderState.snoozedUntil.removeValue(forKey: key)
        settingsStore.saveReminderState(reminderState)
        applyPetEvents([.meetingStarted])
        presentMeeting(event, key: key)
    }

    public func startFocus() {
        guard pomodoro.phase == .idle else { return }

        let result = CoordinatorPolicy.focusRequest(
            events: events,
            now: clock.now,
            focusDuration: settings.focusDuration
        )
        if result.effects.contains(where: {
            if case .showFocusOverlap = $0 { return true }
            return false
        }) {
            apply(result)
            return
        }

        send(.startFocus)
    }

    public func startFocusIgnoringOverlap() {
        focusOverlap = nil
        if pomodoro.phase == .idle {
            send(.startFocus, bypassingFocusOverlap: true)
        } else if pomodoro.phase == .focus,
                  pomodoro.isPaused,
                  focusStartPauseReason != nil
        {
            focusStartPauseReason = nil
            send(
                .resume,
                bypassingFocusOverlap: true,
                activatingDeferredFocus: true
            )
        }
    }

    public func performDockPrimaryAction() {
        if pomodoro.phase == .idle {
            startFocus()
        } else {
            pauseOrResume()
        }
        if focusOverlap != nil {
            ensureControlPanelPresented(currentDockHome())
        }
    }

    public func cancelFocusOverlap() {
        focusOverlap = nil
    }

    @discardableResult
    public func requestCalendarAccess(afterExplanation: Bool) async -> Bool {
        guard afterExplanation, started else { return false }
        let refreshEpoch = calendarRefreshEpoch
        calendarStatus = .refreshing
        do {
            let granted = try await calendar.requestFullAccess()
            guard isCalendarRefreshCurrent(refreshEpoch) else { return false }
            guard granted else {
                rejectCalendarEvents(status: .accessDenied, at: clock.now)
                return false
            }
            refreshCalendar()
            return true
        } catch {
            guard isCalendarRefreshCurrent(refreshEpoch) else { return false }
            rejectCalendarEvents(
                status: .unavailable(
                    message: "Calendar access could not be requested. You can continue with Pomodoro only."
                ),
                at: clock.now
            )
            return false
        }
    }

    public func saveSettings(_ newSettings: AppSettings) {
        settingsStore.settings = newSettings
    }

    public func setAmbientExcursionsEnabled(_ enabled: Bool) {
        var updated = settings
        updated.ambientExcursionsEnabled = enabled
        saveSettings(updated)
    }

    public func selectTepalPalette(_ palette: TepalPaletteID) {
        let profile = TepalGrowthProfile(completedFocuses: tepalCompletedFocusCount)
        guard profile.availablePalettes.contains(palette) else { return }

        var updated = settings
        updated.tepalPalette = palette
        saveSettings(updated)
        settings = settingsStore.settings
        renderDock()
    }

    public func dismissTepalUnlock() {
        pendingTepalUnlock = nil
    }

    public func refreshLaunchAtLoginStatus() {
        launchAtLoginStatus = launchAtLoginController.status
        launchAtLoginError = nil
        commitActualLaunchAtLoginStatus()
    }

    public func setLaunchAtLoginEnabled(_ enabled: Bool) {
        launchAtLoginError = nil
        do {
            try launchAtLoginController.setEnabled(enabled)
        } catch {
            launchAtLoginStatus = launchAtLoginController.status
            launchAtLoginError = "Launch at login could not be changed: \(error.localizedDescription)"
            return
        }

        launchAtLoginStatus = launchAtLoginController.status
        commitActualLaunchAtLoginStatus()
    }

    private func commitActualLaunchAtLoginStatus() {
        var updated = settings
        updated.launchAtLoginEnabled = launchAtLoginStatus == .enabled
        settingsStore.settings = updated
        settings = settingsStore.settings
    }

    public func clearAllLocalData() {
        historySaveError = nil
        invalidateCurrentCalendarRefresh()
        settingsStore.clearAll()
        settings = .defaults
        knockCalendar.configure(settings)
        reminderState = ReminderState()
        pendingPreparationEvent = nil
        events = []
        nextEvent = nil
        calendarChoices = []
        calendarStatus = .notRequested
        focusOverlap = nil
        focusStartPauseReason = nil
        activeMeeting = nil
        calendarRefreshRequiredBeforeReminders = false
        pendingRewardReaction = false
        rewardReactionIsActive = false
        rewardReactionEnd = nil
        pausedRewardReactionRemaining = nil
        tepalCompletedFocusCount = 0
        pendingTepalUnlock = nil
        queuedTepalUnlock = nil
        excursionController.hide()

        var resetEngine = PomodoroEngine(settings: settings)
        pomodoro = resetEngine.send(.tick, at: clock.now)
        engine = resetEngine
        var resetPetMachine = PetStateMachine()
        petState = resetPetMachine.send(.timerPhase(pomodoro.phase))
        petMachine = resetPetMachine

        if started {
            restartCalendarRefreshTimer()
            restartAmbientTask()
        }
        renderDock()
        rescheduleTimerTask()
    }

    public func pauseOrResume() {
        guard pomodoro.phase != .idle else { return }
        var activatingDeferredFocus = false
        if pomodoro.phase == .focus,
           pomodoro.isPaused,
           focusStartPauseReason != nil
        {
            let result = CoordinatorPolicy.focusRequest(
                events: events,
                now: clock.now,
                focusDuration: settings.focusDuration
            )
            if result.hasFocusOverlap {
                apply(result)
                return
            }
            activatingDeferredFocus = true
            focusStartPauseReason = nil
            focusOverlap = nil
        }
        send(
            pomodoro.isPaused ? .resume : .pause,
            activatingDeferredFocus: activatingDeferredFocus
        )
    }

    public func skipPhase() {
        guard pomodoro.phase != .idle else { return }
        send(.skip)
    }

    public func snoozeMeeting() {
        guard let activeMeeting else { return }
        let now = clock.now
        var didSnooze = false
        for occurrence in activeMeeting.occurrences {
            didSnooze = ReminderPlanner.snooze(
                occurrence.key,
                state: &reminderState,
                now: now,
                duration: settings.snoozeDuration
            ) || didSnooze
        }
        guard didSnooze else {
            dismissMeeting()
            return
        }

        endActiveMeeting(at: now)
        persistCurrentState()
        renderDock()
        rescheduleTimerTask()

        #if DEBUG
        if activeMeeting.occurrences.contains(where: { $0.event.id == demoMeeting?.id }) {
            Self.reportDemo("snoozed")
        }
        #endif
    }

    public func dismissMeeting() {
        guard let dismissedMeeting = activeMeeting else { return }
        endActiveMeeting(at: clock.now)
        renderDock()
        rescheduleTimerTask()

        #if DEBUG
        if dismissedMeeting.occurrences.contains(where: { $0.event.id == demoMeeting?.id }) {
            Self.reportDemo("dismissed")
        }
        #endif
    }

    public func refreshCalendar() {
        guard started else { return }
        refreshContinuation.yield()
    }

    public func settingsDidChange() {
        handleSettingsChanged()
    }

    public func activateControlPanel() {
        handleActivation()
    }

    private func send(
        _ command: PomodoroCommand,
        bypassingFocusOverlap: Bool = false,
        activatingDeferredFocus: Bool = false
    ) {
        let previous = pomodoro
        let now = clock.now
        pomodoro = engine.send(command, at: now)
        prepareNewFocusIfNeeded(
            from: previous,
            at: now,
            bypassingFocusOverlap: bypassingFocusOverlap
        )
        playFocusStartIfNeeded(
            from: previous,
            activatingDeferredFocus: activatingDeferredFocus
        )
        apply(CoordinatorPolicy.timerTransition(from: previous, to: pomodoro, at: now))
        presentPreparationIfNeeded(from: previous, at: now)
        evaluateReminders(at: now)
        renderDock()
        rescheduleTimerTask()
    }

    private func updateTimer(
        at now: Date,
        evaluateReminders shouldEvaluate: Bool = true,
        focusTransitionContext: FocusTransitionContext = .ordinary
    ) {
        let previous = pomodoro
        pomodoro = engine.send(.tick, at: now)
        prepareNewFocusIfNeeded(
            from: previous,
            at: now,
            focusTransitionContext: focusTransitionContext
        )
        playFocusStartIfNeeded(from: previous)
        apply(CoordinatorPolicy.timerTransition(from: previous, to: pomodoro, at: now))
        presentPreparationIfNeeded(from: previous, at: now)
        if shouldEvaluate {
            evaluateReminders(at: now)
        }
        renderDock()
    }

    private func prepareNewFocusIfNeeded(
        from previous: PomodoroSnapshot,
        at now: Date,
        bypassingFocusOverlap: Bool = false,
        focusTransitionContext: FocusTransitionContext = .ordinary
    ) {
        guard previous.phase != .focus, pomodoro.phase == .focus else {
            if pomodoro.phase != .focus {
                focusStartPauseReason = nil
                focusOverlap = nil
            }
            return
        }

        focusStartPauseReason = pomodoro.isPaused ? .overlapConfirmation : nil
        guard !bypassingFocusOverlap, !pomodoro.isPaused else { return }

        let result = CoordinatorPolicy.focusRequest(
            events: events,
            now: now,
            focusDuration: settings.focusDuration
        )
        guard result.hasFocusOverlap else {
            focusOverlap = nil
            return
        }

        pomodoro = engine.send(.pause, at: now)
        focusStartPauseReason = focusTransitionContext == .wakeBeforeCalendarRefresh
            ? .wakeAutoStartAwaitingCalendar
            : .overlapConfirmation
        apply(result)
    }

    private func apply(_ result: CoordinatorPolicyResult) {
        applyPetEvents(result.petEvents)

        for effect in result.effects {
            switch effect {
            case let .showMeeting(event, key):
                presentMeeting(event, key: key)
            case let .showFocusOverlap(event):
                focusOverlap = event
            case let .recordCompletedFocus(endedAt, duration):
                recordCompletedFocus(at: endedAt, duration: duration)
                playSoundIfEnabled(.focusCompleted)
            case .persist:
                persistCurrentState()
            }
        }
    }

    private func applyPetEvents(_ petEvents: [PetEvent]) {
        for event in petEvents {
            petState = petMachine.send(event)
        }
    }

    private func recordCompletedFocus(at endedAt: Date, duration: TimeInterval?) {
        if let historyStore {
            do {
                let priorProfile = TepalGrowthProfile(
                    completedFocuses: tepalCompletedFocusCount
                )
                _ = try historyStore.recordCompletedFocus(endedAt: endedAt, duration: duration)
                let completedFocusCount = try historyStore
                    .focusHistorySnapshot()
                    .tepalEffectiveCompletedFocusCount
                let updatedProfile = TepalGrowthProfile(
                    completedFocuses: completedFocusCount
                )
                let priorPalettes = Set(priorProfile.availablePalettes)
                historySaveError = nil
                tepalCompletedFocusCount = updatedProfile.completedFocuses
                queuedTepalUnlock = updatedProfile.availablePalettes.first {
                    !priorPalettes.contains($0)
                } ?? queuedTepalUnlock
            } catch {
                historySaveError = "History could not be updated. Your previous growth is preserved."
                pendingTepalUnlock = nil
                queuedTepalUnlock = nil
            }
        }

        pendingRewardReaction = true
        startPendingRewardIfDisplayable(at: clock.now)
    }

    private func startPendingRewardIfDisplayable(at now: Date) {
        guard pendingRewardReaction,
              activeMeeting == nil,
              !rewardReactionIsActive
        else {
            return
        }

        pendingRewardReaction = false
        rewardReactionIsActive = true
        rewardReactionEnd = now.addingTimeInterval(2)
        pausedRewardReactionRemaining = nil
        applyPetEvents([.rewardStarted])
    }

    private func pauseRewardReactionForMeeting(at now: Date) {
        guard rewardReactionIsActive else { return }
        if finishRewardIfDue(at: now) { return }
        guard let rewardReactionEnd else { return }

        let remaining = max(0, rewardReactionEnd.timeIntervalSince(now))
        self.rewardReactionEnd = nil
        guard remaining > 0 else {
            rewardReactionIsActive = false
            pausedRewardReactionRemaining = nil
            applyPetEvents([.rewardEnded])
            return
        }

        pausedRewardReactionRemaining = remaining
    }

    private func resumeRewardReactionAfterMeeting(at now: Date) {
        guard rewardReactionIsActive,
              let pausedRewardReactionRemaining
        else {
            return
        }

        self.pausedRewardReactionRemaining = nil
        rewardReactionEnd = now.addingTimeInterval(pausedRewardReactionRemaining)
    }

    @discardableResult
    private func finishRewardIfDue(at now: Date) -> Bool {
        guard rewardReactionIsActive,
              let rewardReactionEnd,
              rewardReactionEnd <= now
        else {
            return false
        }

        rewardReactionIsActive = false
        self.rewardReactionEnd = nil
        pausedRewardReactionRemaining = nil
        applyPetEvents([.rewardEnded])
        if let queuedTepalUnlock {
            pendingTepalUnlock = queuedTepalUnlock
        }
        queuedTepalUnlock = nil
        return true
    }

    private func evaluateReminders(at now: Date) {
        guard settings.meetingAlertsEnabled,
              !calendarRefreshRequiredBeforeReminders
        else {
            return
        }

        var dueOccurrences: [MeetingOccurrence] = []
        while true {
            let decision = ReminderPlanner.nextDue(
                events: events,
                state: reminderState,
                now: now,
                lead: settings.reminderLead
            )
            guard case let .show(event, key) = decision else { break }
            reminderState.shown.insert(key)
            reminderState.snoozedUntil.removeValue(forKey: key)
            dueOccurrences.append(MeetingOccurrence(event: event, key: key))
        }
        guard !dueOccurrences.isEmpty else { return }

        let hasInitialOccurrence = dueOccurrences.contains {
            !reminderState.snoozeUsed.contains($0.key)
        }
        settingsStore.saveReminderState(reminderState)

        if var activeMeeting {
            let activeKeys = Set(activeMeeting.occurrences.map(\.key))
            activeMeeting.occurrences.append(contentsOf: dueOccurrences.filter {
                !activeKeys.contains($0.key)
            })
            self.activeMeeting = activeMeeting
        } else {
            pauseRewardReactionForMeeting(at: now)
            activeMeeting = ActiveMeeting(occurrences: dueOccurrences)
            applyPetEvents([.excursionEnded, .meetingStarted])
        }

        presentActiveMeeting(playInitialSound: hasInitialOccurrence)
        renderDock()
    }

    private func presentMeeting(
        _ event: CalendarEventSummary,
        key: ReminderOccurrenceKey,
        playInitialSound: Bool = true
    ) {
        pauseRewardReactionForMeeting(at: clock.now)
        activeMeeting = ActiveMeeting(
            occurrences: [MeetingOccurrence(event: event, key: key)]
        )
        presentActiveMeeting(
            playInitialSound: playInitialSound && !reminderState.snoozeUsed.contains(key)
        )
    }

    private func presentActiveMeeting(playInitialSound: Bool) {
        guard let activeMeeting, !activeMeeting.occurrences.isEmpty else { return }
        if playInitialSound {
            playSoundIfEnabled(.meetingReminder)
        }
        let home = currentDockHome()
        let dismiss: () -> Void = { [weak self] in
            self?.dismissMeeting()
        }

        let canSnooze = activeMeeting.occurrences.contains {
            !reminderState.snoozeUsed.contains($0.key)
        }
        if !canSnooze {
            excursionController.showMeetingsWithoutSnooze(
                titles: activeMeeting.titles,
                start: activeMeeting.earliestStart,
                from: home,
                appearance: tepalVisualState,
                onDismiss: dismiss
            )
        } else {
            excursionController.showMeetings(
                titles: activeMeeting.titles,
                start: activeMeeting.earliestStart,
                from: home,
                appearance: tepalVisualState,
                onDismiss: dismiss,
                onSnooze: { [weak self] in self?.snoozeMeeting() }
            )
        }

        #if DEBUG
        if activeMeeting.occurrences.contains(where: { $0.event.id == demoMeeting?.id }) {
            Self.reportDemo("bubble shown")
        }
        #endif
    }

    private func startRefreshLoop() {
        guard started, refreshLoopTask == nil else { return }
        let stream = refreshStream
        refreshLoopTask = Task { @MainActor [weak self] in
            for await _ in stream {
                guard let self, self.started, !Task.isCancelled else { return }
                self.beginCalendarRefresh()
            }
        }
    }

    @discardableResult
    private func beginCalendarRefresh() -> Task<Void, Never> {
        calendarRefreshTask?.cancel()
        let task = Task { @MainActor [weak self] in
            guard let self, self.started, !Task.isCancelled else { return }
            await self.performCalendarRefresh()
        }
        calendarRefreshTask = task
        return task
    }

    private func startCalendarChangeConsumer() {
        guard started, changeConsumerTask == nil else { return }
        let changes = calendar.changes()
        let continuation = refreshContinuation
        changeConsumerTask = Task { @MainActor [weak self] in
            for await _ in changes {
                guard let self, self.started, !Task.isCancelled else { return }
                continuation.yield()
            }
        }
    }

    private func performCalendarRefresh() async {
        let refreshEpoch = calendarRefreshEpoch
        guard isCalendarRefreshCurrent(refreshEpoch) else { return }
        calendarStatus = .refreshing

        #if DEBUG
        if let demoMeeting {
            acceptCalendarEvents([demoMeeting], at: clock.now)
            return
        }
        #endif

        let authorization = await calendar.authorizationStatus()
        guard isCalendarRefreshCurrent(refreshEpoch) else { return }
        let authorizationNow = clock.now
        switch authorization {
        case .fullAccess:
            break
        case .notDetermined:
            rejectCalendarEvents(status: .notRequested, at: authorizationNow)
            return
        case .restricted, .denied, .writeOnly:
            rejectCalendarEvents(status: .accessDenied, at: authorizationNow)
            return
        }

        do {
            let availableCalendars = try await calendar.calendars()
            guard isCalendarRefreshCurrent(refreshEpoch) else { return }
            let calendarsNow = clock.now
            let googleCalendars = availableCalendars
                .filter { $0.sourceEligibility == .requiresGoogleConfirmation }
                .sorted {
                    let sourceOrder = $0.sourceTitle.localizedCaseInsensitiveCompare($1.sourceTitle)
                    if sourceOrder != .orderedSame {
                        return sourceOrder == .orderedAscending
                    }
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
            calendarChoices = googleCalendars
            guard !googleCalendars.isEmpty else {
                clearCalendarEvents(status: .disconnected, at: calendarsNow, clearChoices: false)
                return
            }
            let sourceFiltered = googleCalendars.filter {
                settings.confirmedGoogleSourceIDs.contains($0.sourceID)
            }
            guard !sourceFiltered.isEmpty else {
                clearCalendarEvents(status: .noSelection, at: calendarsNow, clearChoices: false)
                return
            }
            let availableIDs = Set(sourceFiltered.map(\.id))
            let calendarIDs = availableIDs.intersection(settings.enabledCalendarIDs)
            let now = clock.now
            guard !calendarIDs.isEmpty else {
                clearCalendarEvents(status: .noSelection, at: now, clearChoices: false)
                return
            }
            let fetched = try await calendar.events(
                from: now,
                through: now.addingTimeInterval(settings.calendarLookahead),
                calendarIDs: calendarIDs
            )
            guard isCalendarRefreshCurrent(refreshEpoch) else { return }
            let fetchedAt = clock.now
            acceptCalendarEvents(
                fetched.filter { calendarIDs.contains($0.calendarID) },
                at: fetchedAt
            )
        } catch {
            guard isCalendarRefreshCurrent(refreshEpoch) else { return }
            rejectCalendarEvents(
                status: .unavailable(message: "Calendar reminders are temporarily unavailable. Try again."),
                at: clock.now
            )
        }
    }

    private func acceptCalendarEvents(_ fetched: [CalendarEventSummary], at now: Date) {
        calendarRefreshRequiredBeforeReminders = false
        events = ReminderPlanner.eligible(fetched, now: now)
        nextEvent = events.first(where: { $0.start > now })
        calendarStatus = .ready
        reconcileCalendarDerivedState(at: now)
        deliverPendingPreparation(at: now)
        pruneReminderState(at: now)
        evaluateReminders(at: now)
        renderDock()
        rescheduleTimerTask()
    }

    private func rejectCalendarEvents(status: CalendarStatus, at now: Date) {
        clearCalendarEvents(status: status, at: now, clearChoices: true)
    }

    private func clearCalendarEvents(
        status: CalendarStatus,
        at now: Date,
        clearChoices: Bool
    ) {
        calendarRefreshRequiredBeforeReminders = false
        events = []
        nextEvent = nil
        if clearChoices {
            calendarChoices = []
        }
        calendarStatus = status
        reconcileCalendarDerivedState(at: now)
        pruneReminderState(at: now)
        apply(CoordinatorPolicy.calendarFailure())
        rescheduleTimerTask()
    }

    private func reconcileCalendarDerivedState(at now: Date) {
        if focusOverlap != nil || focusStartPauseReason == .wakeAutoStartAwaitingCalendar {
            let result = CoordinatorPolicy.focusRequest(
                events: events,
                now: now,
                focusDuration: settings.focusDuration
            )
            focusOverlap = result.effects.compactMap { effect in
                if case let .showFocusOverlap(event) = effect { return event }
                return nil
            }.first
            if focusStartPauseReason == .wakeAutoStartAwaitingCalendar {
                if focusOverlap == nil {
                    focusStartPauseReason = nil
                    resumeWakeAutoStartedFocus(at: now)
                } else {
                    focusStartPauseReason = .overlapConfirmation
                }
            }
        }

        guard let activeMeeting else { return }
        let currentOccurrences = activeMeeting.occurrences.compactMap { occurrence in
            events.first { event in
                event.id == occurrence.key.eventID
                    && event.start == occurrence.key.start
                    && event.start > now
            }.map { MeetingOccurrence(event: $0, key: occurrence.key) }
        }
        guard !currentOccurrences.isEmpty else {
            endActiveMeetingAfterCalendarChange(at: now)
            return
        }
        guard currentOccurrences != activeMeeting.occurrences else { return }
        self.activeMeeting = ActiveMeeting(occurrences: currentOccurrences)
        presentActiveMeeting(playInitialSound: false)
    }

    private func resumeWakeAutoStartedFocus(at now: Date) {
        guard pomodoro.phase == .focus, pomodoro.isPaused else { return }
        let previous = pomodoro
        pomodoro = engine.send(.resume, at: now)
        playFocusStartIfNeeded(from: previous, activatingDeferredFocus: true)
        apply(CoordinatorPolicy.timerTransition(from: previous, to: pomodoro, at: now))
        presentPreparationIfNeeded(from: previous, at: now)
    }

    private func endActiveMeetingAfterCalendarChange(at now: Date) {
        guard activeMeeting != nil else { return }
        endActiveMeeting(at: now)
    }

    private func endActiveMeeting(at now: Date) {
        excursionController.hide()
        activeMeeting = nil
        applyPetEvents([.meetingEnded])
        resumeRewardReactionAfterMeeting(at: now)
        startPendingRewardIfDisplayable(at: now)
    }

    private func pruneReminderState(at now: Date) {
        let previous = reminderState
        ReminderPlanner.prune(events: events, state: &reminderState, now: now)
        if reminderState != previous {
            settingsStore.saveReminderState(reminderState)
        }
    }

    private func restartCalendarRefreshTimer() {
        calendarRefreshTimer?.invalidate()
        calendarRefreshTimer = nil
        guard started else { return }
        let continuation = refreshContinuation
        let timer = Timer(timeInterval: settings.calendarRefreshInterval, repeats: true) { _ in
            continuation.yield()
        }
        RunLoop.main.add(timer, forMode: .common)
        calendarRefreshTimer = timer
    }

    private func rescheduleTimerTask() {
        timerTask?.cancel()
        timerTask = nil

        guard started, let interval = nextTimerInterval(at: clock.now) else { return }
        let sleep = sleep
        timerTask = Task { @MainActor [weak self] in
            do {
                try await sleep(interval)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.timerTask = nil
            let now = self.clock.now
            self.updateTimer(at: now)
            if self.finishRewardIfDue(at: now) {
                self.renderDock()
            }
            self.rescheduleTimerTask()
        }
    }

    private func nextTimerInterval(at now: Date) -> TimeInterval? {
        var candidates: [TimeInterval] = []

        if let meeting = pomodoro.meetingFocusEvent {
            candidates.append(max(0, meeting.start.addingTimeInterval(-120).timeIntervalSince(now)))
        }

        if let targetEnd = pomodoro.targetEnd {
            candidates.append(min(1, max(0, targetEnd.timeIntervalSince(now))))
        }

        if let rewardReactionEnd {
            candidates.append(max(0, rewardReactionEnd.timeIntervalSince(now)))
        }

        if settings.meetingAlertsEnabled, !calendarRefreshRequiredBeforeReminders {
            for event in events where event.start > now {
                let key = ReminderOccurrenceKey(eventID: event.id, start: event.start)
                guard !reminderState.shown.contains(key) else { continue }

                let due = reminderState.snoozedUntil[key]
                    ?? event.start.addingTimeInterval(-settings.reminderLead)
                candidates.append(max(0, due.timeIntervalSince(now)))
            }
        }

        return candidates.min()
    }

    private func restartAmbientTask() {
        ambientTask?.cancel()
        ambientTask = nil
        guard started else { return }
        let sleep = sleep
        ambientTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.nextAmbientInterval() else { return }
                do {
                    try await sleep(interval)
                } catch {
                    return
                }
                guard !Task.isCancelled, self?.started == true else { return }
                guard let self else { return }
                self.attemptAmbientExcursion()
            }
        }
    }

    private func nextAmbientInterval() -> TimeInterval {
        let sampledJitter = randomJitter()
        let jitter = sampledJitter.isFinite ? min(300, max(0, sampledJitter)) : 0
        return settings.minimumAmbientInterval + jitter
    }

    private func attemptAmbientExcursion() {
        guard settings.ambientExcursionsEnabled,
              petState == .idle,
              activeMeeting == nil,
              !pendingRewardReaction,
              !rewardReactionIsActive,
              !excursionController.isPresented,
              activityMonitor.idleSeconds() < 300
        else {
            return
        }

        applyPetEvents([.excursionStarted])
        renderDock()
        excursionController.showProbe(
            from: currentDockHome(),
            appearance: tepalVisualState
        ) { [weak self] in
            guard let self else { return }
            self.applyPetEvents([.excursionEnded])
            self.renderDock()
        }
    }

    private func installLifecycleObservers() {
        notificationObservers.append(workspaceNotifications.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.started else { return }
                self.persistCurrentState()
            }
        })
        notificationObservers.append(workspaceNotifications.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.started else { return }
                await self.handleWakeOrClockChange()
            }
        })
        notificationObservers.append(applicationNotifications.addObserver(
            forName: .NSSystemClockDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.started else { return }
                await self.handleWakeOrClockChange()
            }
        })
        notificationObservers.append(applicationNotifications.addObserver(
            forName: .NSSystemTimeZoneDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.started else { return }
                await self.handleWakeOrClockChange()
            }
        })
        notificationObservers.append(applicationNotifications.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.started else { return }
                self.refreshLaunchAtLoginStatus()
            }
        })
        notificationObservers.append(applicationNotifications.addObserver(
            forName: SettingsStore.settingsDidChangeNotification,
            object: settingsStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.started else { return }
                self.handleSettingsChanged()
            }
        })
    }

    private func handleWakeOrClockChange() async {
        guard started else { return }
        calendarRefreshRequiredBeforeReminders = true
        timerTask?.cancel()
        timerTask = nil
        let now = clock.now
        updateTimer(
            at: now,
            evaluateReminders: false,
            focusTransitionContext: .wakeBeforeCalendarRefresh
        )
        let refreshTask = beginCalendarRefresh()
        await refreshTask.value
        guard started, !Task.isCancelled else { return }
        _ = finishRewardIfDue(at: clock.now)
        renderDock()
        rescheduleTimerTask()
    }

    private func handleActivation() {
        let located = DockHomeLocator.locate(
            pointer: pointerLocation(),
            screens: screenGeometries()
        )
        if located.usedPointer {
            dockHome = located
        }
        toggleControlPanel(currentDockHome())
    }

    private func handleSettingsChanged() {
        guard started else { return }
        let normalized = settingsStore.settings
        guard normalized != settings else { return }
        invalidateCurrentCalendarRefresh()
        settings = normalized
        knockCalendar.configure(settings)
        if let reconfigured = PomodoroEngine(recovering: pomodoro, settings: normalized) {
            engine = reconfigured
        }
        restartCalendarRefreshTimer()
        restartAmbientTask()
        refreshCalendar()
        rescheduleTimerTask()
        renderDock()
    }

    private func invalidateCalendarRefresh() {
        calendarRefreshEpoch &+= 1
    }

    private func invalidateCurrentCalendarRefresh() {
        invalidateCalendarRefresh()
        calendarRefreshTask?.cancel()
        calendarRefreshTask = nil
    }

    private func isCalendarRefreshCurrent(_ epoch: UInt) -> Bool {
        started && calendarRefreshEpoch == epoch && !Task.isCancelled
    }

    private func currentDockHome() -> DockGeometry {
        dockHome ?? DockHomeLocator.locate(pointer: nil, screens: screenGeometries())
    }

    private func persistCurrentState() {
        let recovery = pomodoro.phase == .idle ? nil : PomodoroRecovery(
            snapshot: pomodoro,
            focusStartDisposition: focusStartPauseReason != nil
                ? .needsOverlapConfirmation
                : .interrupted
        )
        settingsStore.saveTimerRecovery(recovery)
        settingsStore.saveReminderState(reminderState)
    }

    private func playSoundIfEnabled(_ cue: LocalSoundCue) {
        guard settings.soundEnabled else { return }
        soundPlayer.play(cue)
    }

    private func playFocusStartIfNeeded(
        from previous: PomodoroSnapshot,
        activatingDeferredFocus: Bool = false
    ) {
        guard (previous.phase != .focus || activatingDeferredFocus),
              pomodoro.phase == .focus,
              !pomodoro.isPaused
        else { return }
        playSoundIfEnabled(.focusStarted)
    }

    private func renderDock() {
        tileView?.render(tepalVisualState)
    }

    private var effectiveReducedMotion: Bool {
        settings.reducedMotionPreference.resolved(systemSetting: reducedMotion())
    }

    private var timerProgress: Double {
        let total: TimeInterval
        switch pomodoro.phase {
        case .idle:
            return 0
        case .focus:
            total = pomodoro.focusDuration ?? settings.focusDuration
        case .shortBreak:
            total = settings.shortBreakDuration
        case .longBreak:
            total = settings.longBreakDuration
        }

        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - (pomodoro.remaining.timeInterval / total)))
    }

    #if DEBUG
    private static func demoMeetingDelay(in arguments: [String]) -> TimeInterval? {
        guard let flag = arguments.firstIndex(of: "--demo-meeting-seconds"),
              arguments.indices.contains(flag + 1),
              let seconds = TimeInterval(arguments[flag + 1]),
              seconds.isFinite,
              seconds >= 0
        else {
            return nil
        }
        return seconds
    }

    private static func reportDemo(_ message: String) {
        demoLogger.notice("\(message, privacy: .public)")
        FileHandle.standardError.write(Data("Tepal DemoMeeting: \(message)\n".utf8))
    }
    #endif
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds)
            + (TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000)
    }
}

private extension FocusHistorySnapshot {
    var tepalEffectiveCompletedFocusCount: Int {
        let rewardMilestone = rewardIDs.map(\.tepalMilestone).max() ?? 0
        return max(0, completedFocusCount, rewardMilestone)
    }
}

private extension CosmeticReward {
    var tepalMilestone: Int {
        switch self {
        case .glow: 1
        case .sparkle: 4
        case .colorShift: 12
        case .morph: 25
        }
    }
}
