import Foundation
import Testing
@testable import TepalCore

struct DoubleKnockDetectorTests {
    private func replay(pulses: [Double], background: Double = 0, amplitude: Double = 0.06) -> Int {
        var detector = DoubleKnockDetector()
        var count = 0
        for index in 0..<4800 {
            let t = Double(index) / 800
            let impulse = pulses.reduce(0.0) { value, center in
                value + amplitude * exp(-pow((t - center) / 0.007, 2))
            }
            let signal = impulse + background * sin(t * 70)
            if detector.process(time: t, acceleration: SIMD3(signal, 0, 1)) { count += 1 }
        }
        return count
    }
    @Test func recognizesNaturalFastDoubleKnocks() {
        #expect(replay(pulses: [1, 1.185, 3, 3.3]) == 2)
    }
    @Test func recognizesGentlerDoubleKnocks() {
        #expect(replay(pulses: [1, 1.2], amplitude: 0.038) == 1)
    }
    @Test func recognizesFasterAndSlowerDeliberatePairs() {
        #expect(replay(pulses: [1, 1.13]) == 1)
        #expect(replay(pulses: [1, 1.6]) == 1)
    }
    @Test func allowsRetryOneSecondLater() {
        #expect(replay(pulses: [1, 1.185, 2, 2.185]) == 2)
    }
    private func replayRinging(pulses: [Double]) -> Int {
        var detector = DoubleKnockDetector()
        var count = 0
        for index in 0..<3200 {
            let t = Double(index) / 800
            let signal = pulses.reduce(0.0) { value, center in
                let elapsed = t - center
                guard elapsed >= 0 else { return value }
                return value + 0.1 * exp(-elapsed / 0.12) * sin(2 * .pi * 90 * elapsed)
            }
            if detector.process(time: t, acceleration: SIMD3(signal, 0, 1)) { count += 1 }
        }
        return count
    }
    @Test func separatesTwoImpactsWhileTheChassisIsStillRinging() {
        #expect(replayRinging(pulses: [1, 1.18]) == 1)
        #expect(replayRinging(pulses: [1, 1.18, 2.5, 2.68]) == 2)
    }
    @Test func oneRingingImpactDoesNotBecomeADoubleKnock() {
        #expect(replayRinging(pulses: [1]) == 0)
        #expect(replayRinging(pulses: [1, 1.07]) == 0)
    }
    @Test func recognizesFiveMeasuredPairsWithOverlappingRinging() throws {
        // Local 5 ms strength summaries from the session where the old detector
        // recognized zero pairs. No raw acceleration or calendar data is stored.
        let url = try #require(Bundle.module.url(forResource: "macbook-ringing-envelope", withExtension: "csv", subdirectory: "Fixtures"))
        let rows = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").dropFirst()
        var detector = KnockEnvelopeDetector()
        var matches: [Double] = []
        for row in rows {
            let fields = row.split(separator: ",")
            let time = try #require(Double(fields[0]))
            let strength = try #require(Double(fields[1]))
            if detector.process(time: time, rms: strength) { matches.append(time) }
        }
        #expect(matches.count == 5)
        for window in [5.3...5.9, 7.5...8.1, 10.4...11.1, 12.6...13.3, 15.2...15.9] {
            #expect(matches.filter { window.contains($0) }.count == 1)
        }
    }
    @Test func rejectsSingleTooCloseAndTooFarApartImpacts() {
        #expect(replay(pulses: [1]) == 0)
        #expect(replay(pulses: [1, 1.08]) == 0)
        #expect(replay(pulses: [1, 1.7]) == 0)
    }
    @Test func requiresQuietLeadInAndDoesNotCountTriplesTwice() {
        #expect(replay(pulses: [1, 1.185], background: 0.012) == 0)
        #expect(replay(pulses: [1, 1.185, 1.37, 1.555]) == 1)
    }
    @Test func nextEventIsScopedFutureTimedAndNotCancelled() {
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        func event(_ id: String, _ offset: Double, _ cal: String = "work", allDay: Bool = false, cancelled: Bool = false) -> CalendarEventSummary {
            CalendarEventSummary(id: id, title: id, start: now.addingTimeInterval(offset), end: now.addingTimeInterval(offset + 900), calendarID: cal, isAllDay: allDay, isCancelled: cancelled)
        }
        let events = [event("late", 900), event("past", -10), event("other", 5, "personal"), event("all-day", 5, allDay: true), event("cancelled", 5, cancelled: true), event("next", 30)]
        #expect(KnockEventSelection.next(in: events, after: now, calendarIDs: ["work"])?.id == "next")
        #expect(KnockEventSelection.next(in: events, after: now, calendarIDs: []) == nil)
    }
    @Test func optInDefaultsOffAndPersists() throws {
        var settings = AppSettings.defaults
        #expect(!settings.doubleKnockEnabled)
        settings.doubleKnockEnabled = true
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.doubleKnockEnabled)
        let legacy = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(!legacy.doubleKnockEnabled)
    }
}
