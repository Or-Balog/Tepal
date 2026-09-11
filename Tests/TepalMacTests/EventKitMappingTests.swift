import EventKit
import Foundation
import Testing
@testable import TepalMac

struct EventKitMappingTests {
    @Test func everyCalDAVSourceRequiresExplicitGoogleConfirmation() {
        // Break caught: a Google-looking title or identifier is treated as provider proof and calendar content is read without confirmation.
        #expect(EventKitSourceClassifier.eligibility(
            sourceType: .calDAV,
            title: "Google",
            identifier: "account-1"
        ) == .requiresGoogleConfirmation)
        #expect(EventKitSourceClassifier.eligibility(
            sourceType: .calDAV,
            title: "Corporate Calendar",
            identifier: "C8B038DD-2272-43AE-A3C7-60F0748B7C5D"
        ) == .requiresGoogleConfirmation)
        #expect(EventKitSourceClassifier.eligibility(
            sourceType: .calDAV,
            title: "Google Migration Archive",
            identifier: "not-a-google-account"
        ) == .requiresGoogleConfirmation)
    }

    @Test func nonCalDAVSourcesCannotBeConfirmedAsGoogle() {
        // Break caught: a misleading Exchange or local account name appears in the Google-source confirmation flow.
        #expect(EventKitSourceClassifier.eligibility(
            sourceType: .exchange,
            title: "Google migration",
            identifier: "exchange-1"
        ) == .ineligible)
        #expect(EventKitSourceClassifier.eligibility(
            sourceType: .local,
            title: "Google",
            identifier: "local-1"
        ) == .ineligible)
    }

    @Test func protocolInputMapsEveryRawEventKitField() throws {
        // Break caught: production extraction chooses the fallback identifier, swaps dates, or reads the wrong calendar/status field.
        let event = FakeEventKitEvent(
            eventIdentifier: "occurrence-42",
            calendarItemIdentifier: "fallback-item-99",
            title: "Design review",
            startDate: Date(timeIntervalSinceReferenceDate: 20_000),
            endDate: Date(timeIntervalSinceReferenceDate: 20_900),
            calendarIdentifier: "calendar-7",
            isAllDay: true,
            status: .canceled
        )

        let summary = try #require(EventKitEventMapper.summary(from: event))

        #expect(summary.id == "occurrence-42")
        #expect(summary.title == "Design review")
        #expect(summary.start == Date(timeIntervalSinceReferenceDate: 20_000))
        #expect(summary.end == Date(timeIntervalSinceReferenceDate: 20_900))
        #expect(summary.calendarID == "calendar-7")
        #expect(summary.isAllDay)
        #expect(summary.isCancelled)
    }

    @Test func missingOccurrenceIdentifierAndTitleUseDocumentedFallbacks() throws {
        // Break caught: an unavailable occurrence identifier or title fails to use the item identifier and exact display fallback.
        let event = FakeEventKitEvent(
            eventIdentifier: nil,
            calendarItemIdentifier: "calendar-item-43",
            title: nil,
            startDate: Date(timeIntervalSinceReferenceDate: 30_000),
            endDate: Date(timeIntervalSinceReferenceDate: 30_600),
            calendarIdentifier: "calendar-8",
            isAllDay: false,
            status: .confirmed
        )

        let summary = try #require(EventKitEventMapper.summary(from: event))

        #expect(summary.id == "calendar-item-43")
        #expect(summary.title == "Untitled event")
        #expect(!summary.isCancelled)
    }
}

private struct FakeEventKitEvent: EventKitEventInput {
    let eventIdentifier: String!
    let calendarItemIdentifier: String
    let title: String!
    let startDate: Date!
    let endDate: Date!
    let calendarIdentifier: String
    let isAllDay: Bool
    let status: EKEventStatus
}
