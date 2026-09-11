public enum PetState: Equatable, Sendable {
    case idle
    case focus
    case rest
    case meetingAlert
    case reward
    case excursion
}

public enum PetEvent: Equatable, Sendable {
    case timerPhase(PomodoroPhase)
    case meetingStarted
    case meetingEnded
    case rewardStarted
    case rewardEnded
    case excursionStarted
    case excursionEnded
}

public struct PetStateMachine: Sendable {
    public private(set) var state: PetState

    private var baseState: PetState
    private var meetingIsActive = false
    private var rewardIsActive = false
    private var excursionIsActive = false

    public init() {
        state = .idle
        baseState = .idle
    }

    @discardableResult
    public mutating func send(_ event: PetEvent) -> PetState {
        switch event {
        case let .timerPhase(phase):
            baseState = Self.state(for: phase)
        case .meetingStarted:
            meetingIsActive = true
        case .meetingEnded:
            meetingIsActive = false
        case .rewardStarted:
            rewardIsActive = true
        case .rewardEnded:
            rewardIsActive = false
        case .excursionStarted:
            excursionIsActive = true
        case .excursionEnded:
            excursionIsActive = false
        }

        state = resolvedState()
        return state
    }

    private static func state(for phase: PomodoroPhase) -> PetState {
        switch phase {
        case .idle:
            .idle
        case .focus:
            .focus
        case .shortBreak, .longBreak:
            .rest
        }
    }

    private func resolvedState() -> PetState {
        if meetingIsActive { return .meetingAlert }
        if rewardIsActive { return .reward }
        if excursionIsActive { return .excursion }
        return baseState
    }
}
