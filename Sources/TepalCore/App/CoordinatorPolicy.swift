import Foundation

public enum CoordinatorEffect: Equatable, Sendable {
    case showMeeting(CalendarEventSummary, ReminderOccurrenceKey)
    case showFocusOverlap(CalendarEventSummary)
    case recordCompletedFocus(Date, duration: TimeInterval? = nil)
    case persist
}

public struct CoordinatorPolicyResult: Equatable, Sendable {
    public let petEvents: [PetEvent]
    public let effects: [CoordinatorEffect]

    public init(petEvents: [PetEvent] = [], effects: [CoordinatorEffect] = []) {
        self.petEvents = petEvents
        self.effects = effects
    }

    public var hasFocusOverlap: Bool {
        effects.contains {
            if case .showFocusOverlap = $0 { return true }
            return false
        }
    }
}

public enum CoordinatorPolicy {
    public static func timerTransition(
        from previous: PomodoroSnapshot,
        to current: PomodoroSnapshot,
        at now: Date
    ) -> CoordinatorPolicyResult {
        var petEvents: [PetEvent] = []
        var effects: [CoordinatorEffect] = []

        if previous.phase != current.phase {
            petEvents.append(.timerPhase(current.phase))
        }
        if current.completedFocusCount > previous.completedFocusCount {
            effects.append(.recordCompletedFocus(previous.targetEnd ?? now, duration: previous.focusDuration))
        }
        if persistedTimerStateChanged(from: previous, to: current) {
            effects.append(.persist)
        }

        return CoordinatorPolicyResult(petEvents: petEvents, effects: effects)
    }

    public static func reminder(_ decision: ReminderDecision) -> CoordinatorPolicyResult {
        switch decision {
        case .none:
            CoordinatorPolicyResult()
        case let .show(event, key):
            CoordinatorPolicyResult(
                petEvents: [.excursionEnded, .meetingStarted],
                effects: [.showMeeting(event, key), .persist]
            )
        }
    }

    public static func calendarFailure() -> CoordinatorPolicyResult {
        CoordinatorPolicyResult()
    }

    public static func focusRequest(
        events: [CalendarEventSummary],
        now: Date,
        focusDuration: TimeInterval
    ) -> CoordinatorPolicyResult {
        let proposedEnd = now.addingTimeInterval(max(0, focusDuration))
        guard let overlap = ReminderPlanner.overlappingEvent(
            events: events,
            now: now,
            proposedEnd: proposedEnd
        ) else {
            return CoordinatorPolicyResult()
        }

        return CoordinatorPolicyResult(effects: [.showFocusOverlap(overlap)])
    }

    private static func persistedTimerStateChanged(
        from previous: PomodoroSnapshot,
        to current: PomodoroSnapshot
    ) -> Bool {
        previous.phase != current.phase
            || previous.targetEnd != current.targetEnd
            || previous.completedFocusCount != current.completedFocusCount
            || previous.isPaused != current.isPaused
    }
}
