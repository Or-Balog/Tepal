import AppKit
import TepalCore
import Foundation
import Testing
@testable import TepalApp

@MainActor
struct KnockCalendarControllerTests {
    @Test func checkingAgainRefreshesTheExistingCardEvenForTheSameEvent() async throws {
        let controller = KnockCalendarController(calendar: KnockTestCalendar(), visual: {
            TepalVisualState(pose: .ready, timerProgress: 0, palette: .moonFern,
                               growth: .init(completedFocuses: 0), reducedMotion: true)
        })
        defer { controller.stop() }
        var settings = AppSettings.defaults
        settings.enabledCalendarIDs = ["work"]
        settings.confirmedGoogleSourceIDs = ["google"]
        controller.configure(settings)
        await controller.showNextEvent()?.value
        let firstPanel = try #require(controller.panel)
        let firstDate = try #require(controller.lastAnnouncementAt)
        #expect(controller.announcementCount == 1)
        let firstContent = firstPanel.contentViewController
        await controller.showNextEvent()?.value
        #expect(controller.panel === firstPanel)
        #expect(controller.announcementCount == 2)
        #expect(try #require(controller.lastAnnouncementAt) >= firstDate)
        #expect(controller.panel?.contentViewController !== firstContent)
        #expect(controller.recognizedKnockCount == 0) // Preview must not pretend a physical gesture occurred.
    }

    @Test func announcementStaysVisibleWhileAnotherAppIsActive() async throws {
        let controller = KnockCalendarController(calendar: KnockTestCalendar(), visual: {
            TepalVisualState(pose: .ready, timerProgress: 0, palette: .moonFern,
                               growth: .init(completedFocuses: 0), reducedMotion: true)
        })
        defer { controller.stop() }
        await controller.showNextEvent()?.value
        let panel = try #require(controller.panel)
        #expect(!panel.hidesOnDeactivate)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
    }

    private func makeController(_ calendar: KnockTestCalendar, show: @escaping (String, String) -> Void) -> KnockCalendarController {
        KnockCalendarController(calendar: calendar, visual: {
            TepalVisualState(pose: .ready, timerProgress: 0, palette: .moonFern,
                               growth: .init(completedFocuses: 0), reducedMotion: true)
        }, showAnnouncement: show)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition(), "Calendar announcement did not arrive")
    }

    @Test func previewReadsOnlyConfirmedSelectedCalendars() async throws {
        let calendar = KnockTestCalendar()
        var titles: [String] = []
        let controller = makeController(calendar) { title, _ in titles.append(title) }
        var settings = AppSettings.defaults
        settings.enabledCalendarIDs = ["work", "unconfirmed"]
        settings.confirmedGoogleSourceIDs = ["google"]
        controller.configure(settings)
        controller.showNextEvent()
        try await waitUntil { !titles.isEmpty }
        #expect(titles == ["Design review"])
        #expect(await calendar.queriedIDs == ["work"])
        #expect(await calendar.accessRequests == 0)
        #expect(!settings.doubleKnockEnabled)
        controller.stop()
    }

    @Test func deniedAccessShowsSetupWithoutPromptingOrReadingEvents() async throws {
        let calendar = KnockTestCalendar(authorization: .denied)
        var titles: [String] = []
        let controller = makeController(calendar) { title, _ in titles.append(title) }
        controller.showNextEvent()
        try await waitUntil { !titles.isEmpty }
        #expect(titles == ["Connect your calendar"])
        #expect(await calendar.accessRequests == 0)
        #expect(await calendar.queriedIDs == nil)
        controller.stop()
    }

    @Test func changingSelectedCalendarsDiscardsInFlightAnnouncement() async throws {
        let calendar = KnockTestCalendar(delay: true)
        var titles: [String] = []
        let controller = makeController(calendar) { title, _ in titles.append(title) }
        var settings = AppSettings.defaults
        settings.enabledCalendarIDs = ["work"]
        settings.confirmedGoogleSourceIDs = ["google"]
        controller.configure(settings)
        let request = controller.showNextEvent()
        // Hold the fetch explicitly so concurrent UI tests cannot race a timed delay.
        for _ in 0..<200 {
            if await calendar.queriedIDs != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await calendar.queriedIDs == ["work"])
        settings.enabledCalendarIDs = []
        controller.configure(settings)
        await calendar.finishQuery()
        await request?.value
        #expect(titles.isEmpty)
        controller.stop()
    }
}

private actor KnockTestCalendar: CalendarReading {
    let authorization: CalendarAuthorizationStatus
    let delay: Bool
    private(set) var accessRequests = 0
    private(set) var queriedIDs: Set<String>?
    private var pending: CheckedContinuation<Void, Never>?
    init(authorization: CalendarAuthorizationStatus = .fullAccess, delay: Bool = false) {
        self.authorization = authorization; self.delay = delay
    }
    func authorizationStatus() -> CalendarAuthorizationStatus { authorization }
    func requestFullAccess() -> Bool { accessRequests += 1; return false }
    func calendars() -> [CalendarDescriptor] {
        [CalendarDescriptor(id: "work", title: "Work", sourceTitle: "Google", sourceID: "google"),
         CalendarDescriptor(id: "unconfirmed", title: "Other", sourceTitle: "Other", sourceID: "other")]
    }
    func events(from: Date, through: Date, calendarIDs: Set<String>) async -> [CalendarEventSummary] {
        queriedIDs = calendarIDs
        if delay { await withCheckedContinuation { pending = $0 } }
        return [CalendarEventSummary(id: "meeting", title: "Design review", start: from.addingTimeInterval(600),
                                     end: from.addingTimeInterval(1800), calendarID: "work", isAllDay: false, isCancelled: false)]
    }
    func finishQuery() { pending?.resume(); pending = nil }
    nonisolated func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}
