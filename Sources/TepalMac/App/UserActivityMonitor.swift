import CoreGraphics
import Foundation

public protocol UserActivityReading: Sendable {
    func idleSeconds() -> TimeInterval
}

public struct SystemUserActivityMonitor: UserActivityReading {
    public init() {}

    public func idleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: .null
        )
    }
}
