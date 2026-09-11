import Testing
@testable import TepalCore

struct PetStateMachineTests {
    @Test func timerPhasesProduceTheirAmbientPetStates() {
        // Break caught: a timer phase maps to the wrong visible ambient pet state.
        var machine = PetStateMachine()

        #expect(machine.send(.timerPhase(.idle)) == .idle)
        #expect(machine.send(.timerPhase(.focus)) == .focus)
        #expect(machine.send(.timerPhase(.shortBreak)) == .rest)
        #expect(machine.send(.timerPhase(.longBreak)) == .rest)
    }

    @Test func rewardTakesPriorityOverExcursionAndRestoresTheActiveExcursion() {
        // Break caught: a completion reward loses to an active excursion or ending it drops the excursion.
        var machine = PetStateMachine()

        #expect(machine.send(.timerPhase(.focus)) == .focus)
        #expect(machine.send(.excursionStarted) == .excursion)
        #expect(machine.send(.rewardStarted) == .reward)
        #expect(machine.send(.rewardEnded) == .excursion)
        #expect(machine.send(.excursionEnded) == .focus)
    }

    @Test func meetingInterruptsExcursionAndReturnsToTheMostRecentPomodoroBase() {
        // Break caught: ending a meeting restores stale idle state instead of the latest timer-derived state.
        var machine = PetStateMachine()

        #expect(machine.send(.excursionStarted) == .excursion)
        #expect(machine.send(.meetingStarted) == .meetingAlert)
        #expect(machine.send(.timerPhase(.shortBreak)) == .meetingAlert)
        #expect(machine.send(.excursionEnded) == .meetingAlert)
        #expect(machine.send(.meetingEnded) == .rest)
    }

    @Test func meetingTakesPriorityOverRewardAndEndingItRevealsReward() {
        // Break caught: a meeting alert does not outrank a timer-completion reward.
        var machine = PetStateMachine()

        #expect(machine.send(.rewardStarted) == .reward)
        #expect(machine.send(.meetingStarted) == .meetingAlert)
        #expect(machine.send(.meetingEnded) == .reward)
        #expect(machine.send(.rewardEnded) == .idle)
    }
}
