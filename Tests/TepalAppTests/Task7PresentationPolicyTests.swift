import AppKit
import TepalCore
import TepalMac
import SwiftUI
import Testing
@testable import TepalApp

@MainActor
struct Task7PresentationPolicyTests {
    @Test func distantMeetingUsesLocalCalendarDayAndNearMeetingUsesCountdown() {
        // Break caught: UTC boundaries or a raw minute count misrepresent a distant local meeting.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 7200)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 23, minute: 30))!
        let tomorrow = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 10))!
        let locale = Locale(identifier: "en_US_POSIX")
        #expect(LivingTerrariumPresentation.eventTimeDescription(start: tomorrow, now: now, calendar: calendar, locale: locale).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") == "Tomorrow at 10:00 AM")
        #expect(LivingTerrariumPresentation.eventTimeDescription(start: now.addingTimeInterval(900), now: now, calendar: calendar, locale: locale) == "in 15m")
        #expect(LivingTerrariumPresentation.eventTimeDescription(start: now, now: now, calendar: calendar, locale: locale) == "Starting now")
    }

    @Test func growthProgressTracksNextTierAndStopsAtMaturity() {
        // Break caught: the progress button targets the wrong milestone or asks for sessions after maturity.
        #expect(LivingTerrariumPresentation.growthProgressLine(for: .init(completedFocuses: 2)) == "2 more focuses to Sprouted")
        #expect(LivingTerrariumPresentation.growthProgressLine(for: .init(completedFocuses: 3)) == "1 more focus to Sprouted")
        #expect(LivingTerrariumPresentation.growthProgressLine(for: .init(completedFocuses: 25)) == "Fully grown · Explore palettes")
    }

    @Test func onboardingUsesFourTepalChapters() {
        // Break caught: onboarding loses a workflow page or regresses to the generic Tepal chapter language.
        #expect(TepalOnboardingPresentation.chapters.map(\.title) == [
            "A quiet place on your Mac",
            "Bring Google Calendar through macOS",
            "Read meetings, never change them",
            "Name your familiar",
        ])
    }

    @Test func normalCanvasCadenceAdvancesAtTheSemanticPoseRate() {
        let state = TepalVisualState(
            pose: .ready,
            timerProgress: 0,
            palette: .moonFern,
            growth: TepalGrowthProfile(completedFocuses: 0),
            reducedMotion: false
        )

        #expect(TepalCanvasCadence.frameInterval(for: state) == 0.5)
        #expect(TepalCanvasCadence.frameIndex(at: 10, for: state) == 20)
        #expect(TepalCanvasCadence.frameIndex(at: 10.49, for: state) == 20)
        #expect(TepalCanvasCadence.frameIndex(at: 10.50, for: state) == 21)
    }

    @Test func reducedMotionAndStaticSemanticInterruptionUseOneSettledCanvasFrame() {
        let growth = TepalGrowthProfile(completedFocuses: 0)
        let reduced = TepalVisualState(
            pose: .ready,
            timerProgress: 0,
            palette: .moonFern,
            growth: growth,
            reducedMotion: true
        )
        let interrupted = TepalVisualState(
            pose: .meetingAttentive,
            timerProgress: 0,
            palette: .moonFern,
            growth: growth,
            reducedMotion: false
        )

        #expect(TepalCanvasCadence.frameInterval(for: reduced) == nil)
        #expect(TepalCanvasCadence.frameIndex(at: 10.50, for: reduced) == 0)
        #expect(TepalCanvasCadence.frameInterval(for: interrupted) == nil)
        #expect(TepalCanvasCadence.frameIndex(at: 10.50, for: interrupted) == 0)
    }

    @Test func everyPoseUsesCompactBodyLocalPersonalityCaptionCopy() {
        // Break caught: the visual caption reuses a full accessibility sentence and spans the creature.
        let expected: [(TepalPose, String)] = [
            (.ready, "curious"),
            (.preparingFocus, "settling"),
            (.keepingWatch, "watching"),
            (.pausedCurious, "curious"),
            (.resting, "resting"),
            (.meetingAttentive, "attentive"),
            (.completionBloom, "blooming"),
            (.walking, "wandering"),
            (.staticFallback, "still"),
        ]

        for (pose, copy) in expected {
            let presentation = TepalPersonalityCaptionPresentation.make(for: pose)
            #expect(presentation.text == copy)
            #expect(presentation.text.split(separator: " ").count <= 2)
            #expect(presentation.text.count <= 10)
            #expect(presentation.maximumWidth <= 68)
            #expect(presentation.fontSize <= 9)
            #expect(presentation.horizontalPadding <= 6)
            #expect(presentation.verticalOffset >= 28 && presentation.verticalOffset <= 32)
        }
    }

    @Test func calendarExplanationStatesTheRealPermissionBoundary() {
        // Break caught: the access request understates macOS's permission or implies Tepal can mutate events.
        let copy = TepalOnboardingPresentation.calendarPermissionExplanation

        #expect(copy.contains("Full Calendar Access"))
        #expect(copy.contains("read upcoming titles and times"))
        #expect(copy.contains("no calendar save, edit, or delete path"))
    }

    @Test func flagshipCompositionMatchesTheApprovedShelf() {
        // Break caught: the flagship panel regresses to generic labels or dimensions instead of approved option C.
        #expect(ControlPanelController.panelSize == TepalLayout.panelSize)
        #expect(LivingTerrariumPresentation.phaseEyebrow(for: .idle) == "FOCUS RITUAL")
        #expect(LivingTerrariumPresentation.phaseEyebrow(for: .focus) == "FOCUS RITUAL")
        #expect(LivingTerrariumPresentation.phaseEyebrow(for: .shortBreak) == "SHORT REST")
        #expect(LivingTerrariumPresentation.phaseEyebrow(for: .longBreak) == "LONG REST")
        #expect(LivingTerrariumPresentation.leafLabel(for: .seedling) == "LEAF 01")
        #expect(LivingTerrariumPresentation.leafLabel(for: .glowing) == "LEAF 02")
        #expect(LivingTerrariumPresentation.leafLabel(for: .sprouted) == "LEAF 03")
        #expect(LivingTerrariumPresentation.leafLabel(for: .flourishing) == "LEAF 04")
        #expect(LivingTerrariumPresentation.leafLabel(for: .mature) == "LEAF 05")
        #expect(LivingTerrariumPresentation.primaryActionTitle(phase: .idle, isPaused: false) == "BEGIN FOCUS")
        #expect(LivingTerrariumPresentation.primaryActionTitle(phase: .focus, isPaused: false) == "PAUSE")
        #expect(LivingTerrariumPresentation.primaryActionTitle(phase: .focus, isPaused: true) == "RESUME")
        #expect(LivingTerrariumPresentation.timeString(.seconds(1_458)) == "24:18")
        #expect(LivingTerrariumPresentation.personalityLine(for: .focus) == "Keeping watch.")
        #expect(LivingTerrariumPresentation.personalityLine(for: .meetingAlert) == "Something approaches.")
    }

    @Test func livingTerrariumPresentsTimerCalendarEventAndGrowthState() {
        // Break caught: the compact shelf loses useful fallback copy or exposes raw model values.
        let event = CalendarEventSummary(
            id: "standup",
            title: "Garden standup",
            start: Date(timeIntervalSinceReferenceDate: 1_000),
            end: Date(timeIntervalSinceReferenceDate: 2_000),
            calendarID: "work",
            isAllDay: false,
            isCancelled: false
        )

        #expect(LivingTerrariumPresentation.accessibleTime(.seconds(1_458)) == "24 minutes, 18 seconds")
        #expect(LivingTerrariumPresentation.nextEventLine(
            eventTitle: event.title,
            minutesUntilStart: 42,
            calendarStatus: .ready
        ) == "Next · Garden standup in 42m")
        #expect(LivingTerrariumPresentation.nextEventLine(
            eventTitle: nil,
            minutesUntilStart: nil,
            calendarStatus: .ready
        ) == "No upcoming meetings")
    }

    @Test func accessibleTimerCopyUsesSingularAndPluralUnitsAtBoundaries() {
        // Break caught: VoiceOver announces grammatically incorrect values such as "1 minutes, 1 seconds."
        #expect(LivingTerrariumPresentation.accessibleTime(.seconds(-1)) == "0 minutes, 0 seconds")
        #expect(LivingTerrariumPresentation.accessibleTime(.seconds(1)) == "0 minutes, 1 second")
        #expect(LivingTerrariumPresentation.accessibleTime(.seconds(59)) == "0 minutes, 59 seconds")
        #expect(LivingTerrariumPresentation.accessibleTime(.seconds(60)) == "1 minute, 0 seconds")
        #expect(LivingTerrariumPresentation.accessibleTime(.seconds(61)) == "1 minute, 1 second")
        #expect(LivingTerrariumPresentation.accessibleTime(.seconds(121)) == "2 minutes, 1 second")
    }

    @Test func nextEventAlwaysOccupiesOneConciseLineAndCoversEveryCalendarStatus() {
        // Break caught: a calendar state disappears, stale meeting content wins, or the compact shelf grows extra lines.
        let readyLine = LivingTerrariumPresentation.nextEventLine(
            eventTitle: "Design review",
            minutesUntilStart: 42,
            calendarStatus: .ready
        )
        #expect(readyLine == "Next · Design review in 42m")
        #expect(!readyLine.contains("\n"))
        #expect(LivingTerrariumPresentation.nextEventLine(
            eventTitle: "Started meeting",
            minutesUntilStart: -2,
            calendarStatus: .ready
        ) == "Next · Started meeting in 0m")
        #expect(LivingTerrariumPresentation.nextEventLine(
            eventTitle: "Stale event",
            minutesUntilStart: 42,
            calendarStatus: .notRequested
        ) == "Calendar · Pomodoro only")
        #expect(LivingTerrariumPresentation.nextEventLine(
            eventTitle: "Stale event",
            minutesUntilStart: 42,
            calendarStatus: .refreshing
        ) == "Calendar · Refreshing")
        #expect(LivingTerrariumPresentation.nextEventLine(
            eventTitle: "Stale event",
            minutesUntilStart: 42,
            calendarStatus: .disconnected
        ) == "Calendar · Connect in Settings")
        #expect(LivingTerrariumPresentation.nextEventLine(
            eventTitle: "Stale event",
            minutesUntilStart: 42,
            calendarStatus: .noSelection
        ) == "Calendar · Choose calendars in Settings")
        #expect(LivingTerrariumPresentation.nextEventLine(
            eventTitle: "Stale event",
            minutesUntilStart: 42,
            calendarStatus: .accessDenied
        ) == "Calendar · Access denied")
        #expect(LivingTerrariumPresentation.nextEventLine(
            eventTitle: "Stale event",
            minutesUntilStart: 42,
            calendarStatus: .unavailable(message: "offline")
        ) == "Calendar · Unavailable")
    }

    @Test func nextEventAccessibilityUsesExpandedSemanticCopyForEveryCalendarStatus() {
        // Break caught: VoiceOver receives the abbreviated sighted line, including "42m", or loses a failure state.
        #expect(LivingTerrariumPresentation.nextEventAccessibilityValue(
            eventTitle: "Design review",
            minutesUntilStart: 42,
            calendarStatus: .ready
        ) == "Next meeting, Design review, in 42 minutes")
        #expect(LivingTerrariumPresentation.nextEventAccessibilityValue(
            eventTitle: "Design review",
            minutesUntilStart: 1,
            calendarStatus: .ready
        ) == "Next meeting, Design review, in 1 minute")
        #expect(LivingTerrariumPresentation.nextEventAccessibilityValue(
            eventTitle: "Design review",
            minutesUntilStart: 0,
            calendarStatus: .ready
        ) == "Next meeting, Design review, starts now")
        #expect(LivingTerrariumPresentation.nextEventAccessibilityValue(
            eventTitle: nil,
            minutesUntilStart: nil,
            calendarStatus: .ready
        ) == "No upcoming meetings")
        #expect(LivingTerrariumPresentation.nextEventAccessibilityValue(
            eventTitle: "Stale event",
            minutesUntilStart: 42,
            calendarStatus: .notRequested
        ) == "Calendar has not been connected. Pomodoro only")
        #expect(LivingTerrariumPresentation.nextEventAccessibilityValue(
            eventTitle: "Stale event",
            minutesUntilStart: 42,
            calendarStatus: .refreshing
        ) == "Calendar is refreshing")
        #expect(LivingTerrariumPresentation.nextEventAccessibilityValue(
            eventTitle: "Stale event",
            minutesUntilStart: 42,
            calendarStatus: .disconnected
        ) == "Calendar is disconnected. Connect in Settings")
        #expect(LivingTerrariumPresentation.nextEventAccessibilityValue(
            eventTitle: "Stale event",
            minutesUntilStart: 42,
            calendarStatus: .noSelection
        ) == "No calendars are selected. Choose calendars in Settings")
        #expect(LivingTerrariumPresentation.nextEventAccessibilityValue(
            eventTitle: "Stale event",
            minutesUntilStart: 42,
            calendarStatus: .accessDenied
        ) == "Calendar access is denied")
        #expect(LivingTerrariumPresentation.nextEventAccessibilityValue(
            eventTitle: "Stale event",
            minutesUntilStart: 42,
            calendarStatus: .unavailable(message: "offline")
        ) == "Calendar is unavailable")
    }

    @Test func eventCountdownUsesAnInjectedDateAtMinuteBoundaries() {
        // Break caught: countdown copy reads the process wall clock or rounds a boundary to the wrong displayed minute.
        let now = Date(timeIntervalSinceReferenceDate: 10_000)

        #expect(LivingTerrariumPresentation.minutesUntilStart(
            eventStart: now.addingTimeInterval(60.001),
            now: now
        ) == 2)
        #expect(LivingTerrariumPresentation.minutesUntilStart(
            eventStart: now.addingTimeInterval(60),
            now: now
        ) == 1)
        #expect(LivingTerrariumPresentation.minutesUntilStart(
            eventStart: now.addingTimeInterval(0.001),
            now: now
        ) == 1)
        #expect(LivingTerrariumPresentation.minutesUntilStart(eventStart: now, now: now) == 0)
        #expect(LivingTerrariumPresentation.minutesUntilStart(
            eventStart: now.addingTimeInterval(-60),
            now: now
        ) == 0)
        #expect(LivingTerrariumPresentation.minutesUntilStart(eventStart: nil, now: now) == nil)
    }

    @Test func livingTerrariumTimelineInvalidatesImmediatelyAndOncePerMinute() {
        // Break caught: the idle panel never refreshes event copy, or replaces the minute cadence with a rapid timer.
        let start = Date(timeIntervalSinceReferenceDate: 20_000)
        var entries = LivingTerrariumMinuteSchedule()
            .entries(from: start, mode: .normal)
            .makeIterator()

        #expect(entries.next() == start)
        #expect(entries.next() == start.addingTimeInterval(60))
        #expect(entries.next() == start.addingTimeInterval(120))
    }

    @Test func controlPanelUsesLivingTerrariumDimensions() {
        // Break caught: the hosted view and AppKit panel disagree about the 360-by-640 Living Terrarium contract.
        #expect(ControlPanelController.panelSize == CGSize(width: 360, height: 640))
    }

    @Test func tallerGladeFitsAShortVisibleScreen() {
        let screen = ScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1024, height: 600),
            visibleFrame: CGRect(x: 0, y: 50, width: 1024, height: 525))
        let frame = ControlPanelPlacement.frame(size: TepalLayout.panelSize,
            home: DockGeometry(edge: .bottom, homePoint: CGPoint(x: 512, y: 50), usedPointer: true),
            screens: [screen])
        #expect(screen.visibleFrame.contains(frame))
        #expect(frame.height == 525)
        #expect(frame.width == 360)
    }

    @Test func panelFramePlacesEveryDockEdgeRelativeToItsHome() {
        // Break caught: an edge-specific placement branch is dropped while the panel still clamps on one tested edge.
        let screen = ScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1_000, height: 700),
            visibleFrame: CGRect(x: 0, y: 60, width: 1_000, height: 640)
        )
        let size = CGSize(width: 360, height: 500)
        let cases: [(DockEdge, CGPoint, CGPoint)] = [
            (.bottom, CGPoint(x: 500, y: 60), CGPoint(x: 320, y: 74)),
            (.left, CGPoint(x: 0, y: 350), CGPoint(x: 14, y: 100)),
            (.right, CGPoint(x: 995, y: 350), CGPoint(x: 621, y: 100)),
            (.unknown, CGPoint(x: 500, y: 350), CGPoint(x: 320, y: 100)),
        ]

        for (edge, homePoint, expectedOrigin) in cases {
            let frame = ControlPanelPlacement.frame(
                size: size,
                home: DockGeometry(edge: edge, homePoint: homePoint, usedPointer: true),
                screens: [screen]
            )
            #expect(frame.origin == expectedOrigin)
            #expect(screen.visibleFrame.contains(frame))
        }
    }

    @Test func onboardingOffersPomodoroOnlyForEveryCalendarFailureState() {
        // Break caught: a thrown permission request is rendered as unavailable but offers no way to finish onboarding.
        #expect(OnboardingCalendarAccessPolicy.offersPomodoroOnly(for: .accessDenied))
        #expect(OnboardingCalendarAccessPolicy.offersPomodoroOnly(
            for: .unavailable(message: "Request failed")
        ))
        #expect(OnboardingCalendarAccessPolicy.offersPomodoroOnly(for: .disconnected))
        #expect(OnboardingCalendarAccessPolicy.offersPomodoroOnly(for: .noSelection))

        #expect(!OnboardingCalendarAccessPolicy.offersPomodoroOnly(for: .notRequested))
        #expect(!OnboardingCalendarAccessPolicy.offersPomodoroOnly(for: .refreshing))
        #expect(!OnboardingCalendarAccessPolicy.offersPomodoroOnly(for: .ready))
    }

    @Test func panelFrameUsesDockFallbackWhenCachedPointIsInvalid() {
        // Break caught: a stale/invalid cached Dock point places the control panel off-screen instead of using Dock-edge fallback.
        let screen = ScreenGeometry(
            frame: CGRect(x: 100, y: 100, width: 1_200, height: 800),
            visibleFrame: CGRect(x: 100, y: 160, width: 1_200, height: 740)
        )
        let stale = DockGeometry(edge: .bottom, homePoint: .zero, usedPointer: true)

        let frame = ControlPanelPlacement.frame(
            size: CGSize(width: 320, height: 420),
            home: stale,
            screens: [screen]
        )

        #expect(frame.midX == 700)
        #expect(frame.minY == 174)
        #expect(screen.visibleFrame.contains(frame))
    }

    @Test func panelFrameClampsEveryEdgeInsideTheActiveVisibleFrame() {
        // Break caught: a valid Dock point near a display corner lets the compact panel extend past the visible work area.
        let screen = ScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1_000, height: 700),
            visibleFrame: CGRect(x: 0, y: 60, width: 1_000, height: 640)
        )
        let home = DockGeometry(
            edge: .right,
            homePoint: CGPoint(x: 995, y: 65),
            usedPointer: true
        )

        let frame = ControlPanelPlacement.frame(
            size: CGSize(width: 360, height: 500),
            home: home,
            screens: [screen]
        )

        #expect(frame.minX == 621)
        #expect(frame.minY == 60)
        #expect(screen.visibleFrame.contains(frame))
    }

    @Test func outsideClickLifecycleOwnsLocalAndGlobalCallbacksAndReplacements() {
        // Break caught: a local-only event monitor cannot dismiss the panel when another app receives the click.
        let localTokens = [MouseClickMonitorToken(NSObject()), MouseClickMonitorToken(NSObject())]
        let globalTokens = [MouseClickMonitorToken(NSObject()), MouseClickMonitorToken(NSObject())]
        var localInstallIndex = 0
        var globalInstallIndex = 0
        var localCallbacks: [() -> Void] = []
        var globalCallbacks: [() -> Void] = []
        var removed: [MouseClickMonitorToken] = []
        var callbackCount = 0
        let lifecycle = OutsideClickMonitorLifecycle(
            installLocal: { callback in
                localCallbacks.append(callback)
                defer { localInstallIndex += 1 }
                return localTokens[localInstallIndex]
            },
            installGlobal: { callback in
                globalCallbacks.append(callback)
                defer { globalInstallIndex += 1 }
                return globalTokens[globalInstallIndex]
            },
            remove: { removed.append($0) }
        )

        lifecycle.install { callbackCount += 1 }
        localCallbacks[0]()
        globalCallbacks[0]()
        #expect(callbackCount == 2)

        lifecycle.install { callbackCount += 10 }
        #expect(removed.count == 2)
        #expect(removed[0] === localTokens[0])
        #expect(removed[1] === globalTokens[0])

        localCallbacks[1]()
        globalCallbacks[1]()
        #expect(callbackCount == 22)

        lifecycle.remove()
        lifecycle.remove()
        #expect(removed.count == 4)
        #expect(removed[2] === localTokens[1])
        #expect(removed[3] === globalTokens[1])
    }

    @Test func outsideClickLifecycleRemovesBothTokensOnDeinit() {
        // Break caught: releasing a controller without an explicit close leaks one or both AppKit monitor tokens.
        let local = MouseClickMonitorToken(NSObject())
        let global = MouseClickMonitorToken(NSObject())
        var removed: [MouseClickMonitorToken] = []

        do {
            let lifecycle = OutsideClickMonitorLifecycle(
                installLocal: { _ in local },
                installGlobal: { _ in global },
                remove: { removed.append($0) }
            )
            lifecycle.install {}
        }

        #expect(removed.count == 2)
        #expect(removed[0] === local)
        #expect(removed[1] === global)
    }

    @Test func nonactivatingControlPanelCanBecomeKeyAndEscapeCloses() {
        // Break caught: orderFront displays a non-key panel, so SwiftUI focus, Tab, Space, and Escape do not route to its controls.
        var escapeCount = 0
        let panel = KeyableControlPanel(
            contentRect: CGRect(x: 0, y: 0, width: 360, height: 500),
            styleMask: ControlPanelInteractionPolicy.styleMask,
            backing: .buffered,
            defer: false
        )
        panel.onCancel = { escapeCount += 1 }

        #expect(panel.styleMask.contains(.borderless))
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(!ControlPanelInteractionPolicy.activatesApplication)

        panel.cancelOperation(nil)
        #expect(escapeCount == 1)
    }

    @Test func ensurePresentedNeverTogglesAVisiblePanelClosed() {
        // Break caught: Dock overlap routing reuses toggle and hides the confirmation when the control panel is already visible.
        #expect(ControlPanelInteractionPolicy.presentationAction(isVisible: false) == .showAndMakeKey)
        #expect(ControlPanelInteractionPolicy.presentationAction(isVisible: true) == .makeKey)
    }

    @Test func settingsWindowIsCreatedOnceAndThenReusedUntilClose() {
        // Break caught: every Settings command leaks another window instead of reusing the one owned on demand.
        #expect(SettingsWindowPresentationPolicy.action(hasOwnedWindow: false) == .create)
        #expect(SettingsWindowPresentationPolicy.action(hasOwnedWindow: true) == .reuse)
    }

    @Test func livingTerrariumMoreRoutesThroughTheControlPanelCallback() throws {
        // Break caught: either More action maps to the wrong destination, bypasses the configured control-panel callback, or fails to dismiss the terrarium.
        let suiteName = "Tepal.Task8TerrariumRouting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let coordinator = AppCoordinator(
            settingsStore: SettingsStore(userDefaults: defaults),
            tileView: nil,
            excursionController: ExcursionPanelController(),
            processArguments: []
        )
        defer { coordinator.terminate() }
        let controlPanel = ControlPanelController()
        defer { controlPanel.close() }
        var destinations: [SettingsDestination] = []
        var dismissCount = 0
        controlPanel.configure(
            coordinator: coordinator,
            openSettings: { destinations.append($0) }
        )
        let container = LivingTerrariumContainer(
            coordinator: coordinator,
            onDismiss: { dismissCount += 1 },
            onOpenSettings: { controlPanel.routeSettings($0) }
        )

        container.actions.openSettings()
        container.actions.openHistory()

        #expect(destinations == [.preferences, .history])
        #expect(dismissCount == 2)
    }

    @Test func reusedSettingsWindowReplacesItsHostedDestination() throws {
        // Break caught: reuse keeps the original SettingsView root, opens another window, or merely records a destination without replacing the hosted view.
        let suiteName = "Tepal.Task8SettingsWindow.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let coordinator = AppCoordinator(
            settingsStore: SettingsStore(userDefaults: defaults),
            tileView: nil,
            excursionController: ExcursionPanelController(),
            processArguments: []
        )
        defer { coordinator.terminate() }
        let history = HistoryStoreController(makeStore: { throw Task8PresentationTestError.unavailable })
        let controller = SettingsWindowController()
        defer { controller.close() }

        controller.show(
            destination: .preferences,
            coordinator: coordinator,
            historyStoreController: history
        )
        let first = try #require(controller.presentationState)
        controller.show(
            destination: .history,
            coordinator: coordinator,
            historyStoreController: history
        )
        let second = try #require(controller.presentationState)

        #expect(first.destination == .preferences)
        #expect(second.destination == .history)
        #expect(first.windowIdentity == second.windowIdentity)
        #expect(first.hostingControllerIdentity != second.hostingControllerIdentity)
    }

    @Test func dockMenuTitlesReflectTimerAndAmbientState() {
        // Break caught: the Dock menu advertises Start/Pause or ambient actions that contradict current coordinator state.
        let running = PomodoroSnapshot(
            phase: .focus,
            remaining: .seconds(600),
            targetEnd: Date(timeIntervalSinceReferenceDate: 10_000),
            completedFocusCount: 0,
            isPaused: false
        )
        let paused = PomodoroSnapshot(
            phase: .focus,
            remaining: .seconds(600),
            targetEnd: nil,
            completedFocusCount: 0,
            isPaused: true
        )

        #expect(DockMenuPresentation.primaryTitle(for: running) == "Pause Focus")
        #expect(DockMenuPresentation.primaryTitle(for: paused) == "Resume Focus")
        #expect(DockMenuPresentation.ambientTitle(enabled: true) == "Pause Ambient Excursions")
        #expect(DockMenuPresentation.ambientTitle(enabled: false) == "Resume Ambient Excursions")
    }

    @Test func historyMoodRemainsPositiveForEveryPetState() {
        // Break caught: history introduces punitive/sad language for inactivity or a transient pet state.
        let moods = PetState.allTask7Cases.map {
            HistoryPresentation.mood(totalCompleted: 0, petState: $0)
        }

        #expect(moods == ["Calm", "Focused", "Rested", "Attentive", "Proud", "Curious"])
    }

    @Test func calendarSelectionRequiresExplicitSourceConfirmation() {
        // Break caught: toggling a calendar or a provider-looking title silently confirms an ambiguous CalDAV source.
        var selection = ConfirmedCalendarSelection()

        selection.setCalendar(
            "work-calendar",
            enabled: true,
            sourceID: "opaque-source"
        )
        #expect(selection.calendarIDs.isEmpty)
        #expect(selection.confirmedSourceIDs.isEmpty)

        selection.setSource(
            "opaque-source",
            confirmedAsGoogle: true,
            calendarIDs: ["work-calendar", "personal-calendar"]
        )
        #expect(selection.confirmedSourceIDs == ["opaque-source"])
        #expect(selection.calendarIDs.isEmpty)

        selection.setCalendar(
            "work-calendar",
            enabled: true,
            sourceID: "opaque-source"
        )
        #expect(selection.calendarIDs == ["work-calendar"])

        selection.setSource(
            "opaque-source",
            confirmedAsGoogle: false,
            calendarIDs: ["work-calendar", "personal-calendar"]
        )
        #expect(selection.confirmedSourceIDs.isEmpty)
        #expect(selection.calendarIDs.isEmpty)
    }

    @Test func paletteDrawerCardsKeepTheCuratedOrderAndNames() {
        // Break caught: a reordered or generic card library makes the compact two-column drawer unstable and hard to scan.
        let cards = TepalPalettePresentation.cards(
            profile: TepalGrowthProfile(completedFocuses: 0),
            selected: .moonFern
        )

        #expect(cards.map(\.id) == [
            .moonFern, .twilightPlum, .dewdrop,
            .pollenGold, .emberMoss, .frostBloom,
        ])
        #expect(cards.map(\.name) == [
            "Moon Fern", "Twilight Plum", "Dewdrop",
            "Pollen Gold", "Ember Moss", "Frost Bloom",
        ])
    }

    @Test func paletteDrawerDerivesSelectionLocksAndRequirementsFromGrowth() {
        // Break caught: the library marks an earned palette unavailable, enables a locked card, or associates it with the wrong milestone.
        let cards = TepalPalettePresentation.cards(
            profile: TepalGrowthProfile(completedFocuses: 4),
            selected: .moonFern
        )

        #expect(cards.first(where: { $0.id == .moonFern })?.isSelected == true)
        #expect(cards.first(where: { $0.id == .pollenGold })?.isLocked == false)
        #expect(cards.first(where: { $0.id == .emberMoss })?.isLocked == true)
        #expect(cards.first(where: { $0.id == .emberMoss })?.unlockRequirement == 12)
        #expect(cards.first(where: { $0.id == .frostBloom })?.unlockRequirement == 25)
    }

    @Test func paletteDrawerExposesTextualVoiceOverStateForEveryAvailabilityKind() {
        // Break caught: color-only state leaves VoiceOver users without the selected, available, or locked distinction.
        let cards = TepalPalettePresentation.cards(
            profile: TepalGrowthProfile(completedFocuses: 4),
            selected: .moonFern
        )

        #expect(cards.first(where: { $0.id == .moonFern })?.accessibilityValue == "Selected")
        #expect(cards.first(where: { $0.id == .pollenGold })?.accessibilityValue == "Available")
        #expect(cards.first(where: { $0.id == .emberMoss })?.accessibilityValue ==
            "Locked. Unlock at 12 completed focuses")
    }

    @Test func lockedPaletteCardDoesNotProduceSelectionIntent() {
        // Break caught: activating a locked card reaches coordinator selection and can make unavailable palettes appear equipped.
        let cards = TepalPalettePresentation.cards(
            profile: TepalGrowthProfile(completedFocuses: 0),
            selected: .moonFern
        )
        let locked = try! #require(cards.first(where: { $0.id == .emberMoss }))
        let available = try! #require(cards.first(where: { $0.id == .dewdrop }))

        #expect(TepalPalettePresentation.selectionIntent(for: locked) == nil)
        #expect(TepalPalettePresentation.selectionIntent(for: available) == .dewdrop)
    }

    @Test func pollenGoldUnlockUsesTheApprovedPersonalityLine() {
        // Break caught: an unlock reveal loses the reviewed Tepal personality copy.
        #expect(TepalPalettePresentation.unlockLine(for: .pollenGold) ==
            "A warm color found its way into the glade.")
    }

    @Test func paletteDrawerPreviewRetainsTheExactCoordinatorVisualState() {
        // Break caught: the drawer rebuilds or substitutes preview state, so the displayed Tepal palette, growth, pose, or motion setting drifts from the coordinator.
        let visualState = TepalVisualState(
            pose: .keepingWatch,
            timerProgress: 0.73,
            palette: .emberMoss,
            growth: TepalGrowthProfile(completedFocuses: 12),
            reducedMotion: true
        )

        #expect(TepalPaletteDrawerPresentation.previewState(for: visualState) == visualState)
    }

    @Test func moreOwnsEverySecondaryAction() {
        // Break caught: a secondary action leaks back onto the primary shelf or the menu exposes an unavailable skip action while idle.
        #expect(TepalMorePresentation.actions(phase: .focus) == [
            .skipCurrentPhase, .palettesAndGrowth, .settings, .history,
        ])
        #expect(TepalMorePresentation.actions(phase: .idle) == [
            .palettesAndGrowth, .settings, .history,
        ])
    }

    @Test func unlockRevealNeverChangesSelection() {
        // Break caught: presenting a newly earned palette quietly equips it instead of preserving the user's active color choice.
        let state = TepalUnlockPresentation.make(
            unlocked: .pollenGold,
            selected: .moonFern
        )

        #expect(state.palette == .pollenGold)
        #expect(state.selectedPalette == .moonFern)
        #expect(state.line == "A warm color found its way into the glade.")
    }

    @Test func previewFailureKeepsSelectionAndHasLocalCopy() {
        // Break caught: preview rendering failure is hidden, or it implies a palette-selection change that never occurred.
        let status = TepalPalettePreviewStatus.unavailable

        #expect(status.message == "Preview unavailable. Your current palette is unchanged.")
    }

    @Test func paletteGrowthSummaryUsesConciseSingularAndPluralLeafCopy() {
        // Break caught: the botanical progress copy duplicates the leaf word or uses the wrong singular/plural focus count.
        #expect(
            TepalPaletteDrawerPresentation.growthLine(
                for: TepalGrowthProfile(completedFocuses: 1)
            ) == "3 focuses until Leaf 03"
        )
        #expect(
            TepalPaletteDrawerPresentation.growthLine(
                for: TepalGrowthProfile(completedFocuses: 3)
            ) == "1 focus until Leaf 03"
        )
    }

    @Test func renderedTerrariumUnlockRevealKeepsBothActionsAccessibleAndNonSelecting() throws {
        // Break caught: habitat accessibility containment hides the rendered unlock controls, or either action selects the newly unlocked palette.
        let visualState = TepalVisualState(
            pose: .ready,
            timerProgress: 0,
            palette: .moonFern,
            growth: TepalGrowthProfile(completedFocuses: 4),
            reducedMotion: true
        )
        var selectedPalette = TepalPaletteID.moonFern
        var dismissCount = 0
        let root = NSHostingView(
            rootView: LivingTerrariumView(
                state: LivingTerrariumState(
                    visualState: visualState,
                    phase: .idle,
                    remaining: .seconds(1_500),
                    isPaused: false,
                    personalityLine: "Something new took root.",
                    nextEventLine: "No upcoming meetings",
                    calendarAccessibilityValue: "No upcoming meetings",
                    pendingUnlock: .pollenGold
                ),
                actions: LivingTerrariumActions(
                    primary: {},
                    skip: {},
                    selectPalette: { selectedPalette = $0 },
                    dismissUnlock: { dismissCount += 1 },
                    openSettings: {},
                    openHistory: {}
                )
            )
        )
        root.frame = NSRect(origin: .zero, size: TepalLayout.panelSize)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: TepalLayout.panelSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = root
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        window.layoutIfNeeded()

        let viewPalette = try #require(
            root.descendantButton(
                labeled: "View the unlocked Pollen Gold palette"
            )
        )
        let dismiss = try #require(
            root.descendantButton(
                labeled: "Dismiss Pollen Gold unlock"
            )
        )

        #expect(viewPalette.isAccessibilityElement())
        #expect(dismiss.isAccessibilityElement())
        #expect(viewPalette.accessibilityPerformPress())
        #expect(dismissCount == 1)
        #expect(selectedPalette == .moonFern)

        #expect(dismiss.accessibilityPerformPress())
        #expect(dismissCount == 2)
        #expect(selectedPalette == .moonFern)
    }
}

@MainActor
private extension NSView {
    func descendantButton(labeled label: String) -> NSButton? {
        if let button = self as? NSButton, button.accessibilityLabel() == label {
            return button
        }
        return subviews.lazy.compactMap { $0.descendantButton(labeled: label) }.first
    }
}

private extension PetState {
    static let allTask7Cases: [PetState] = [
        .idle,
        .focus,
        .rest,
        .meetingAlert,
        .reward,
        .excursion,
    ]
}

private enum Task8PresentationTestError: Error {
    case unavailable
}
