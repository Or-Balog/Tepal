import TepalCore
import TepalMac
import Foundation
import SwiftUI

struct LivingTerrariumState: Equatable {
    let visualState: TepalVisualState
    let phase: PomodoroPhase
    let remaining: Duration
    let isPaused: Bool
    let personalityLine: String
    let nextEventLine: String
    let calendarAccessibilityValue: String
    let pendingUnlock: TepalPaletteID?
    var historySaveError: String? = nil
    var meetingFocusTitle: String? = nil
    var meetingFocusEnd: Date? = nil
}

struct LivingTerrariumActions {
    let primary: () -> Void
    let skip: () -> Void
    let selectPalette: (TepalPaletteID) -> Void
    let dismissUnlock: () -> Void
    let openSettings: () -> Void
    let openHistory: () -> Void
    var focusUntilMeeting: () -> Void = {}
}

enum TepalMoreAction: Equatable {
    case skipCurrentPhase
    case palettesAndGrowth
    case settings
    case history
}

enum TepalMorePresentation {
    static func actions(phase: PomodoroPhase) -> [TepalMoreAction] {
        phase == .idle
            ? [.palettesAndGrowth, .settings, .history]
            : [.skipCurrentPhase, .palettesAndGrowth, .settings, .history]
    }
}

struct LivingTerrariumMinuteSchedule: TimelineSchedule, Sendable {
    struct Entries: Sequence, IteratorProtocol, Sendable {
        private var date: Date

        init(startingAt date: Date) {
            self.date = date
        }

        mutating func next() -> Date? {
            defer { date = date.addingTimeInterval(60) }
            return date
        }

        func makeIterator() -> Self { self }
    }

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        Entries(startingAt: startDate)
    }
}

struct TepalHabitatAnimationTrigger: Equatable {
    let pose: TepalPose
    let reducedMotion: Bool

    init(state: TepalVisualState) {
        pose = state.pose
        reducedMotion = state.reducedMotion
    }
}

enum LivingTerrariumPresentation {
    static func phaseEyebrow(for phase: PomodoroPhase) -> String {
        switch phase {
        case .idle, .focus: "FOCUS RITUAL"
        case .shortBreak: "SHORT REST"
        case .longBreak: "LONG REST"
        }
    }

    static func leafLabel(for tier: TepalGrowthTier) -> String {
        switch tier {
        case .seedling: "LEAF 01"
        case .glowing: "LEAF 02"
        case .sprouted: "LEAF 03"
        case .flourishing: "LEAF 04"
        case .mature: "LEAF 05"
        }
    }

    static func growthTitle(for tier: TepalGrowthTier) -> String {
        switch tier {
        case .seedling: "Seedling"
        case .glowing: "Glowing"
        case .sprouted: "Sprouted"
        case .flourishing: "Flourishing"
        case .mature: "Mature"
        }
    }

    static func primaryActionTitle(phase: PomodoroPhase, isPaused: Bool) -> String {
        phase == .idle ? "BEGIN FOCUS" : (isPaused ? "RESUME" : "PAUSE")
    }

    static func nextEventLine(
        eventTitle: String?,
        minutesUntilStart: Int?,
        calendarStatus: CalendarStatus,
        eventStart: Date? = nil,
        now: Date = Date()
    ) -> String {
        guard calendarStatus == .ready else {
            return switch calendarStatus {
            case .notRequested: "Calendar · Pomodoro only"
            case .refreshing: "Calendar · Refreshing"
            case .disconnected: "Calendar · Connect in Settings"
            case .noSelection: "Calendar · Choose calendars in Settings"
            case .accessDenied: "Calendar · Access denied"
            case .unavailable: "Calendar · Unavailable"
            case .ready: "No upcoming meetings"
            }
        }
        guard let eventTitle, let minutesUntilStart else {
            return "No upcoming meetings"
        }
        guard let eventStart else { return "Next · \(eventTitle) in \(max(0, minutesUntilStart))m" }
        return "Next · \(eventTitle) · \(eventTimeDescription(start: eventStart, now: now))"
    }

    static func nextEventAccessibilityValue(
        eventTitle: String?,
        minutesUntilStart: Int?,
        calendarStatus: CalendarStatus,
        eventStart: Date? = nil,
        now: Date = Date()
    ) -> String {
        guard calendarStatus == .ready else {
            return switch calendarStatus {
            case .notRequested: "Calendar has not been connected. Pomodoro only"
            case .refreshing: "Calendar is refreshing"
            case .disconnected: "Calendar is disconnected. Connect in Settings"
            case .noSelection: "No calendars are selected. Choose calendars in Settings"
            case .accessDenied: "Calendar access is denied"
            case .unavailable: "Calendar is unavailable"
            case .ready: "No upcoming meetings"
            }
        }
        guard let eventTitle, let minutesUntilStart else {
            return "No upcoming meetings"
        }
        if let eventStart, minutesUntilStart >= 60 {
            return "Next meeting, \(eventTitle), \(eventTimeDescription(start: eventStart, now: now))"
        }
        let minutes = max(0, minutesUntilStart)
        guard minutes > 0 else {
            return "Next meeting, \(eventTitle), starts now"
        }
        let unit = minutes == 1 ? "minute" : "minutes"
        return "Next meeting, \(eventTitle), in \(minutes) \(unit)"
    }

    static func eventTimeDescription(
        start: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current
    ) -> String {
        let minutes = max(0, Int(ceil(start.timeIntervalSince(now) / 60)))
        if minutes == 0 { return "Starting now" }
        if minutes < 60 { return "in \(minutes)m" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.timeStyle = .short
        let time = formatter.string(from: start)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: start)).day ?? 0
        if days == 0 { return "Today at \(time)" }
        if days == 1 { return "Tomorrow at \(time)" }
        formatter.timeStyle = .none
        if days < 7 {
            formatter.setLocalizedDateFormatFromTemplate("EEEE")
        } else {
            formatter.dateStyle = .medium
        }
        return "\(formatter.string(from: start)) at \(time)"
    }

    static func growthProgressLine(for profile: TepalGrowthProfile) -> String {
        guard let milestone = profile.nextMilestone else { return "Fully grown · Explore palettes" }
        let remaining = milestone - profile.completedFocuses
        let nextTier = TepalGrowthProfile(completedFocuses: milestone).tier
        return "\(remaining) more \(remaining == 1 ? "focus" : "focuses") to \(growthTitle(for: nextTier))"
    }

    static func minutesUntilStart(eventStart: Date?, now: Date) -> Int? {
        eventStart.map {
            max(0, Int(ceil($0.timeIntervalSince(now) / 60)))
        }
    }

    static func timeString(_ duration: Duration) -> String {
        let seconds = boundedSeconds(duration)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    static func accessibleTime(_ duration: Duration) -> String {
        let seconds = boundedSeconds(duration)
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        let minuteUnit = minutes == 1 ? "minute" : "minutes"
        let secondUnit = remainingSeconds == 1 ? "second" : "seconds"
        return "\(minutes) \(minuteUnit), \(remainingSeconds) \(secondUnit)"
    }

    static func personalityLine(for state: PetState) -> String {
        switch state {
        case .idle: "The glade is quiet."
        case .focus: "Keeping watch."
        case .rest: "A little light returns."
        case .meetingAlert: "Something approaches."
        case .reward: "Something new took root."
        case .excursion: "A curious path opens."
        }
    }

    private static func boundedSeconds(_ duration: Duration) -> Int {
        max(0, Int(duration.timeInterval.rounded(.up)))
    }
}

struct TepalPersonalityCaptionPresentation: Equatable {
    let text: String
    let maximumWidth: CGFloat
    let fontSize: CGFloat
    let horizontalPadding: CGFloat
    let verticalOffset: CGFloat

    static func make(for pose: TepalPose) -> TepalPersonalityCaptionPresentation {
        let text = switch pose {
        case .ready, .pausedCurious: "curious"
        case .preparingFocus: "settling"
        case .keepingWatch: "watching"
        case .resting: "resting"
        case .meetingAttentive: "attentive"
        case .completionBloom: "blooming"
        case .walking: "wandering"
        case .staticFallback: "still"
        }
        return TepalPersonalityCaptionPresentation(
            text: text,
            maximumWidth: 68,
            fontSize: 8,
            horizontalPadding: 6,
            verticalOffset: 30
        )
    }
}

struct LivingTerrariumView: View {
    @FocusState private var primaryActionFocused: Bool
    @State private var isPaletteDrawerPresented = false

    let state: LivingTerrariumState
    let actions: LivingTerrariumActions

    private var palette: TepalPalette {
        TepalTheme.palette(for: state.visualState.palette)
    }

    var body: some View {
        VStack(spacing: 0) {
            habitat
                .frame(height: TepalLayout.habitatHeight)
            controlShelf
                .frame(height: TepalLayout.shelfHeight)
        }
        .frame(width: TepalLayout.panelSize.width, height: TepalLayout.panelSize.height)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color(nsColor: palette.habitatBase).opacity(0.91))
        }
        .clipShape(shellShape)
        .overlay {
            shellShape
                .stroke(Color(nsColor: palette.primaryText).opacity(0.12), lineWidth: 1)
        }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .onAppear { primaryActionFocused = true }
        .sheet(isPresented: $isPaletteDrawerPresented) {
            TepalPaletteDrawer(
                visualState: state.visualState,
                onSelect: actions.selectPalette
            )
        }
    }

    private var habitat: some View {
        return ZStack {
            TepalHabitatView(state: state.visualState)
                .accessibilityValue(state.personalityLine)
                .accessibilityIdentifier("terrarium.tepal")

            HStack {
                Text(Date.now, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                Spacer()
                Image(systemName: "leaf")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color(nsColor: palette.secondaryText))
            .padding(24)
            .frame(maxHeight: .infinity, alignment: .top)
            .accessibilityHidden(true)

            if let pendingUnlock = state.pendingUnlock {
                TepalUnlockReveal(
                    state: TepalUnlockPresentation.make(
                        unlocked: pendingUnlock,
                        selected: state.visualState.palette
                    ),
                    onViewPalette: {
                        actions.dismissUnlock()
                        isPaletteDrawerPresented = true
                    },
                    onDismiss: actions.dismissUnlock
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    private var phaseStatus: String {
        let phaseName: String = switch state.phase {
        case .idle: "Ready to focus"
        case .focus: "Focus"
        case .shortBreak: "Short rest"
        case .longBreak: "Long rest"
        }
        if let end = state.meetingFocusEnd {
            return "\(state.isPaused ? "Paused" : "Focus") until \(end.formatted(date: .omitted, time: .shortened)) · 2 min to prepare"
        }
        if state.isPaused { return "\(phaseName) paused · Take your time" }
        if state.visualState.pose == .completionBloom { return "Focus complete · \(phaseName)" }
        return state.phase == .idle ? phaseName : "\(phaseName) · \(state.personalityLine)"
    }

    private var controlShelf: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(LivingTerrariumPresentation.timeString(state.remaining))
                .font(.system(size: TepalLayout.timerPointSize, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(nsColor: palette.primaryText))
                .monospacedDigit()
                .tracking(-1.4)
                .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
                .contentTransition(.numericText(countsDown: true))
                .animation(
                    state.visualState.reducedMotion ? nil : .easeOut(duration: 0.18),
                    value: state.remaining
                )
                .accessibilityLabel("Pomodoro time remaining")
                .accessibilityValue(LivingTerrariumPresentation.accessibleTime(state.remaining))
                .accessibilityIdentifier("control.timer-value")

            Text(phaseStatus)
                .font(.system(size: 14))
                .foregroundStyle(Color(nsColor: palette.secondaryText))
                .padding(.bottom, 22)
                .accessibilityLabel("Pomodoro phase")
                .accessibilityValue(phaseStatus)
                .accessibilityIdentifier("control.phase")

            HStack(spacing: 10) {
                Button(
                    LivingTerrariumPresentation.primaryActionTitle(
                        phase: state.phase,
                        isPaused: state.isPaused
                    ).localizedCapitalized,
                    action: actions.primary
                )
                .buttonStyle(TepalPrimaryButtonStyle(palette: state.visualState.palette))
                .keyboardShortcut(.space, modifiers: [])
                .focused($primaryActionFocused)
                .accessibilityLabel(primaryActionAccessibilityLabel)
                .accessibilityIdentifier("control.primary-action")

                moreMenu
            }
            .frame(height: TepalLayout.primaryControlHeight)
            .padding(.bottom, 17)

            Rectangle()
                .fill(Color(nsColor: palette.divider).opacity(0.72))
                .frame(height: 1)

            Text(state.historySaveError ?? state.nextEventLine)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color(nsColor: palette.secondaryText))
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 14)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(state.historySaveError == nil ? "Next event" : "History status")
                .accessibilityValue(state.historySaveError ?? state.calendarAccessibilityValue)
                .accessibilityIdentifier("control.next-event")

            Button {
                isPaletteDrawerPresented = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "leaf")
                    Text(LivingTerrariumPresentation.growthProgressLine(for: state.visualState.growth))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color(nsColor: palette.leaf))
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Palettes and growth")
            .accessibilityValue(LivingTerrariumPresentation.growthProgressLine(for: state.visualState.growth))
            .accessibilityIdentifier("control.growth-progress")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, TepalLayout.shelfInset)
        .padding(.top, 0)
        .padding(.bottom, 18)
        .background(Color(nsColor: palette.habitatBase).opacity(0.96))
    }

    private var moreMenu: some View {
        Menu {
            if let title = state.meetingFocusTitle {
                Button("Focus until my next meeting · 2 min prep", action: actions.focusUntilMeeting)
                    .help("\(title) · Ends 2 minutes early to prepare")
                Divider()
            }
            ForEach(TepalMorePresentation.actions(phase: state.phase), id: \.self) { action in
                moreMenuItem(for: action)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(nsColor: palette.primaryText))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(
            width: TepalLayout.compactControlWidth,
            height: TepalLayout.primaryControlHeight
        )
        .background(
            Color(nsColor: palette.habitatAccent),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color(nsColor: palette.moreControlBorder), lineWidth: 1.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .fixedSize()
        .accessibilityLabel("More Tepal controls")
        .accessibilityIdentifier("control.more")
    }

    @ViewBuilder
    private func moreMenuItem(for action: TepalMoreAction) -> some View {
        switch action {
        case .skipCurrentPhase:
            Button("Skip Current Phase", action: actions.skip)
        case .palettesAndGrowth:
            Button("Palettes and Growth") {
                isPaletteDrawerPresented = true
            }
        case .settings:
            Button("Settings", action: actions.openSettings)
        case .history:
            Button("History", action: actions.openHistory)
        }
    }

    private var shellShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: TepalLayout.shellRadius, style: .continuous)
    }

    private var primaryActionAccessibilityLabel: String {
        switch state.phase {
        case .idle: "Begin focus session"
        case .focus, .shortBreak, .longBreak:
            state.isPaused ? "Resume Pomodoro phase" : "Pause Pomodoro phase"
        }
    }
}

struct LivingTerrariumContainer: View {
    let coordinator: AppCoordinator
    let onDismiss: () -> Void
    let onOpenSettings: (SettingsDestination) -> Void

    var body: some View {
        TimelineView(LivingTerrariumMinuteSchedule()) { context in
            LivingTerrariumView(state: state(at: context.date), actions: actions)
                .alert(
                    "Meeting overlaps this focus",
                    isPresented: Binding(
                        get: { coordinator.focusOverlap != nil },
                        set: { if !$0 { coordinator.cancelFocusOverlap() } }
                    ),
                    presenting: coordinator.focusOverlap
                ) { _ in
                    Button("Cancel", role: .cancel) {
                        coordinator.cancelFocusOverlap()
                    }
                    .accessibilityLabel("Cancel focus start")
                    .accessibilityIdentifier("overlap.cancel")
                    Button("Start Anyway") {
                        coordinator.startFocusIgnoringOverlap()
                    }
                    .accessibilityLabel("Start focus despite meeting overlap")
                    .accessibilityIdentifier("overlap.start-anyway")
                } message: { event in
                    Text("\(event.title) starts at \(event.start.formatted(date: .omitted, time: .shortened)).")
                }
        }
    }

    private func state(at date: Date) -> LivingTerrariumState {
        let minutesUntilStart = LivingTerrariumPresentation.minutesUntilStart(
            eventStart: coordinator.nextEvent?.start,
            now: date
        )
        let line = LivingTerrariumPresentation.nextEventLine(
            eventTitle: coordinator.nextEvent?.title,
            minutesUntilStart: minutesUntilStart,
            calendarStatus: coordinator.calendarStatus,
            eventStart: coordinator.nextEvent?.start,
            now: date
        )
        return LivingTerrariumState(
            visualState: coordinator.tepalVisualState,
            phase: coordinator.pomodoro.phase,
            remaining: coordinator.pomodoro.remaining,
            isPaused: coordinator.pomodoro.isPaused,
            personalityLine: LivingTerrariumPresentation.personalityLine(for: coordinator.petState),
            nextEventLine: line,
            calendarAccessibilityValue: LivingTerrariumPresentation.nextEventAccessibilityValue(
                eventTitle: coordinator.nextEvent?.title,
                minutesUntilStart: minutesUntilStart,
                calendarStatus: coordinator.calendarStatus,
                eventStart: coordinator.nextEvent?.start,
                now: date
            ),
            pendingUnlock: coordinator.pendingTepalUnlock,
            historySaveError: coordinator.historySaveError,
            meetingFocusTitle: coordinator.meetingFocusCandidate?.title,
            meetingFocusEnd: coordinator.pomodoro.meetingFocusEvent?.start.addingTimeInterval(-120)
        )
    }

    var actions: LivingTerrariumActions {
        LivingTerrariumActions(
            primary: {
                if coordinator.pomodoro.phase == .idle {
                    coordinator.startFocus()
                } else {
                    coordinator.pauseOrResume()
                }
            },
            skip: { coordinator.skipPhase() },
            selectPalette: { coordinator.selectTepalPalette($0) },
            dismissUnlock: { coordinator.dismissTepalUnlock() },
            openSettings: { openSecondaryDestination(.preferences) },
            openHistory: { openSecondaryDestination(.history) },
            focusUntilMeeting: { coordinator.startFocusUntilNextMeeting() }
        )
    }

    private func openSecondaryDestination(_ destination: SettingsDestination) {
        onDismiss()
        onOpenSettings(destination)
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
