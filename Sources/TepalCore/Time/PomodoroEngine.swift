import Foundation

public enum PomodoroPhase: String, Codable, Sendable {
    case idle
    case focus
    case shortBreak
    case longBreak
}

public enum PomodoroCommand: Sendable {
    case startFocus
    case startFocusUntilMeeting(CalendarEventSummary)
    case pause
    case resume
    case skip
    case reset
    case tick
}

public struct PomodoroSnapshot: Codable, Equatable, Sendable {
    public let phase: PomodoroPhase
    public let remaining: Duration
    public let targetEnd: Date?
    public let completedFocusCount: Int
    public let isPaused: Bool
    public let focusDuration: TimeInterval?
    public let meetingFocusEvent: CalendarEventSummary?

    public init(
        phase: PomodoroPhase,
        remaining: Duration,
        targetEnd: Date?,
        completedFocusCount: Int,
        isPaused: Bool,
        focusDuration: TimeInterval? = nil,
        meetingFocusEvent: CalendarEventSummary? = nil
    ) {
        self.phase = phase
        self.remaining = remaining
        self.targetEnd = targetEnd
        self.completedFocusCount = completedFocusCount
        self.isPaused = isPaused
        self.focusDuration = focusDuration
        self.meetingFocusEvent = meetingFocusEvent
    }
}

public struct PomodoroEngine: Sendable {
    public let settings: AppSettings

    private var phase: PomodoroPhase
    private var targetEnd: Date?
    private var pausedRemaining: Duration?
    private var completedFocusCount: Int
    private var focusDuration: TimeInterval?
    private var meetingFocusEvent: CalendarEventSummary?

    public init(settings: AppSettings = .defaults) {
        self.settings = settings.normalizedForPersistence()
        phase = .idle
        targetEnd = nil
        pausedRemaining = nil
        completedFocusCount = 0
        focusDuration = nil
    }

    public init?(recovering snapshot: PomodoroSnapshot, settings: AppSettings = .defaults) {
        guard Self.isValid(snapshot) else { return nil }

        self.settings = settings.normalizedForPersistence()
        phase = snapshot.phase
        targetEnd = snapshot.targetEnd
        pausedRemaining = snapshot.isPaused ? snapshot.remaining : nil
        completedFocusCount = snapshot.completedFocusCount
        focusDuration = snapshot.focusDuration
        meetingFocusEvent = snapshot.meetingFocusEvent
    }

    public mutating func send(_ command: PomodoroCommand, at now: Date) -> PomodoroSnapshot {
        // Elapsed time is settled before the command runs. A command aimed at the
        // phase that just ended is stale — the transition it asked for has already
        // happened, and applying it again would skip or pause the phase the user
        // just earned — so it is dropped once the phase has settled.
        //
        // Reset is the exception: it clears the timer whatever phase is showing, so
        // dropping it strands a timer that expired unobserved, typically because the
        // Mac slept through the deadline.
        if settleElapsedTime(at: now) {
            guard case .reset = command else { return snapshot(at: now) }
        }

        switch command {
        case let .startFocusUntilMeeting(event):
            let duration = event.start.timeIntervalSince(now) - 120
            guard phase == .idle, duration.isFinite, duration >= 60, !event.isAllDay, !event.isCancelled else { return snapshot(at: now) }
            phase = .focus
            meetingFocusEvent = event
            focusDuration = duration
            targetEnd = event.start.addingTimeInterval(-120)
        case .startFocus:
            if phase == .idle {
                phase = .focus
                focusDuration = settings.focusDuration
                targetEnd = deadline(after: duration(for: .focus), from: now)
            } else if let remaining = pausedRemaining {
                if let meeting = meetingFocusEvent {
                    let end = meeting.start.addingTimeInterval(-120)
                    let lostTime = max(0, timeInterval(from: remaining) - end.timeIntervalSince(now))
                    focusDuration = max(0.001, (focusDuration ?? 0) - lostTime)
                    targetEnd = end
                } else {
                    targetEnd = deadline(after: remaining, from: now)
                }
                pausedRemaining = nil
            }
        case .pause:
            if let targetEnd {
                pausedRemaining = remaining(until: targetEnd, from: now)
                self.targetEnd = nil
            }
        case .resume:
            if let pausedRemaining {
                if let meeting = meetingFocusEvent {
                    let end = meeting.start.addingTimeInterval(-120)
                    let lostTime = max(0, timeInterval(from: pausedRemaining) - end.timeIntervalSince(now))
                    focusDuration = max(0.001, (focusDuration ?? 0) - lostTime)
                    targetEnd = end
                } else {
                    targetEnd = deadline(after: pausedRemaining, from: now)
                }
                self.pausedRemaining = nil
            }
        case .skip:
            if meetingFocusEvent != nil {
                finishMeetingFocus(completed: false)
            } else if phase != .idle {
                advance(completingFocus: false, at: now)
            }
        case .reset:
            phase = .idle
            targetEnd = nil
            pausedRemaining = nil
            completedFocusCount = 0
            focusDuration = nil
            meetingFocusEvent = nil
        case .tick:
            break
        }

        return snapshot(at: now)
    }

    /// Applies the transition that elapsed time alone has already earned, and
    /// reports whether the phase moved.
    private mutating func settleElapsedTime(at now: Date) -> Bool {
        if let meeting = meetingFocusEvent, meeting.start.addingTimeInterval(-120) <= now {
            finishMeetingFocus(completed: pausedRemaining == nil)
            return true
        }
        if let targetEnd, targetEnd <= now {
            advance(completingFocus: phase == .focus, at: now)
            return true
        }
        return false
    }

    private mutating func finishMeetingFocus(completed: Bool) {
        if completed { completedFocusCount += 1 }
        phase = .idle
        targetEnd = nil
        pausedRemaining = nil
        focusDuration = nil
        meetingFocusEvent = nil
    }

    private static func isValid(_ snapshot: PomodoroSnapshot) -> Bool {
        if snapshot.meetingFocusEvent != nil && snapshot.phase != .focus { return false }
        if let duration = snapshot.focusDuration, !duration.isFinite || duration <= 0 { return false }
        guard snapshot.remaining >= .zero, snapshot.completedFocusCount >= 0 else { return false }

        switch snapshot.phase {
        case .idle:
            return snapshot.remaining == .zero && snapshot.targetEnd == nil && !snapshot.isPaused
        case .focus, .shortBreak, .longBreak:
            if snapshot.isPaused {
                return snapshot.targetEnd == nil
            }
            return snapshot.targetEnd != nil
        }
    }

    private mutating func advance(completingFocus: Bool, at now: Date) {
        targetEnd = nil

        switch phase {
        case .focus:
            if completingFocus {
                completedFocusCount += 1
            }
            phase = completingFocus && completedFocusCount.isMultiple(of: settings.longBreakEvery)
                ? .longBreak
                : .shortBreak
        case .shortBreak, .longBreak:
            phase = .focus
        case .idle:
            return
        }

        focusDuration = phase == .focus ? settings.focusDuration : nil

        if settings.autoStartNextPhase {
            targetEnd = deadline(after: duration(for: phase), from: now)
            pausedRemaining = nil
        } else {
            pausedRemaining = duration(for: phase)
        }
    }

    private func snapshot(at now: Date) -> PomodoroSnapshot {
        PomodoroSnapshot(
            phase: phase,
            remaining: targetEnd.map { remaining(until: $0, from: now) } ?? pausedRemaining ?? duration(for: phase),
            targetEnd: targetEnd,
            completedFocusCount: completedFocusCount,
            isPaused: pausedRemaining != nil,
            focusDuration: focusDuration,
            meetingFocusEvent: meetingFocusEvent
        )
    }

    private func duration(for phase: PomodoroPhase) -> Duration {
        switch phase {
        case .idle:
            return .zero
        case .focus:
            return .seconds(settings.focusDuration)
        case .shortBreak:
            return .seconds(settings.shortBreakDuration)
        case .longBreak:
            return .seconds(settings.longBreakDuration)
        }
    }

    private func remaining(until end: Date, from now: Date) -> Duration {
        .seconds(max(0, end.timeIntervalSince(now)))
    }

    private func deadline(after duration: Duration, from now: Date) -> Date {
        now.addingTimeInterval(timeInterval(from: duration))
    }

    private func timeInterval(from duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
