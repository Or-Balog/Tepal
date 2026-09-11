import AppKit
import TepalCore
import Testing
@testable import TepalMac

@MainActor
struct ExcursionPanelLayoutTests {
    @Test func meetingCreatureUsesExcursionSurfaceWithoutTimerRing() throws {
        // Break caught: a meeting's embedded character continues to use the Dock surface and can draw a timer ring.
        let view = makeMeetingView(reducedMotion: true)
        defer { view.stopCountdown() }

        let creature = try #require(view.firstDescendant(ofType: TepalTileView.self))
        #expect(creature.renderedSurface == .excursion)
        #expect(creature.renderedVisualState.pose == .meetingAttentive)
    }

    @Test func meetingHierarchyRemainsFunctionalAndNotColorOnly() throws {
        // Break caught: decorative meeting treatment removes an actionable or readable reminder element.
        let view = makeMeetingView(reducedMotion: true)
        defer { view.stopCountdown() }

        #expect(view.descendant(withAccessibilityIdentifier: "meeting.context") != nil)
        #expect(view.descendant(withAccessibilityIdentifier: "meeting.title") != nil)
        #expect(view.descendant(withAccessibilityIdentifier: "meeting.start-time") != nil)
        #expect(view.descendant(withAccessibilityIdentifier: "meeting.countdown") != nil)
        #expect(view.descendant(withAccessibilityIdentifier: "meeting.dismiss") != nil)
        #expect(view.descendant(withAccessibilityIdentifier: "meeting.snooze") != nil)
    }

    @Test func meetingControlsDoNotFollowTheSelectedCharacterPalette() throws {
        // Break caught: the selected character palette recolors reminder controls instead of remaining character-only.
        let frostBloom = MeetingPresentationView(
            titles: ["Design review"],
            start: Date(timeIntervalSinceReferenceDate: 250_000),
            appearance: TepalVisualState(
                pose: .ready,
                timerProgress: 0.5,
                palette: .frostBloom,
                growth: TepalGrowthProfile(completedFocuses: 4),
                reducedMotion: true
            ),
            creatureOnRight: false,
            target: NSObject(),
            dismissAction: #selector(NSObject.description),
            snoozeAction: #selector(NSObject.description)
        )
        let dewdrop = MeetingPresentationView(
            titles: ["Design review"],
            start: Date(timeIntervalSinceReferenceDate: 250_000),
            appearance: TepalVisualState(
                pose: .ready,
                timerProgress: 0.5,
                palette: .dewdrop,
                growth: TepalGrowthProfile(completedFocuses: 4),
                reducedMotion: true
            ),
            creatureOnRight: false,
            target: NSObject(),
            dismissAction: #selector(NSObject.description),
            snoozeAction: #selector(NSObject.description)
        )
        defer {
            frostBloom.stopCountdown()
            dewdrop.stopCountdown()
        }

        let frostDismiss = try #require(
            frostBloom.descendant(withAccessibilityIdentifier: "meeting.dismiss") as? NSButton
        )
        let dewdropDismiss = try #require(
            dewdrop.descendant(withAccessibilityIdentifier: "meeting.dismiss") as? NSButton
        )

        #expect(frostDismiss.bezelColor == dewdropDismiss.bezelColor)
    }

    @Test func meetingPresentationKeepsAppearanceAndAccessibleMeaningBeyondCoral() throws {
        // Break caught: the meeting panel falls back to Moon Fern seedling art or communicates meeting state by coral alone.
        let appearance = TepalVisualState(
            pose: .resting,
            timerProgress: 0.42,
            palette: .frostBloom,
            growth: TepalGrowthProfile(completedFocuses: 25),
            reducedMotion: true
        )
        let view = MeetingPresentationView(
            titles: ["A very important event title"],
            start: Date(timeIntervalSinceReferenceDate: 250_000),
            appearance: appearance,
            creatureOnRight: false,
            target: NSObject(),
            dismissAction: #selector(NSObject.description),
            snoozeAction: #selector(NSObject.description)
        )
        defer { view.stopCountdown() }
        view.layoutSubtreeIfNeeded()

        let creature = try #require(view.firstDescendant(ofType: TepalTileView.self))
        let title = try #require(view.descendant(withAccessibilityIdentifier: "meeting.title") as? NSTextField)
        let meetingLabel = try #require(view.descendant(withAccessibilityIdentifier: "meeting.context") as? NSTextField)
        let botanicalSignal = try #require(view.descendant(withAccessibilityIdentifier: "meeting.signal"))
        let dismiss = try #require(view.descendant(withAccessibilityIdentifier: "meeting.dismiss") as? NSButton)
        let snooze = try #require(view.descendant(withAccessibilityIdentifier: "meeting.snooze") as? NSButton)

        #expect(creature.renderedVisualState == appearance.replacingPose(.meetingAttentive))
        #expect(title.accessibilityLabel() == "Meeting title")
        #expect(title.accessibilityValue()?.contains("A very important event title") == true)
        #expect(meetingLabel.stringValue == "MEETING")
        #expect(botanicalSignal.accessibilityLabel() == "Meeting botanical signal")
        #expect(dismiss.frame.height >= 44)
        #expect(snooze.frame.height >= 44)
    }

    @Test func meetingMetadataUsesReadableTypeWithinTheApprovedPanelSize() throws {
        // Break caught: the context, start time, or countdown silently drops below the 12-point readable-text floor.
        let view = MeetingPresentationView(
            titles: ["Design review"],
            start: Date(timeIntervalSinceReferenceDate: 250_000),
            appearance: TepalVisualState(
                pose: .ready,
                timerProgress: 0,
                palette: .moonFern,
                growth: TepalGrowthProfile(completedFocuses: 0),
                reducedMotion: true
            ),
            creatureOnRight: false,
            target: NSObject(),
            dismissAction: #selector(NSObject.description),
            snoozeAction: #selector(NSObject.description)
        )
        defer { view.stopCountdown() }
        view.layoutSubtreeIfNeeded()

        let context = try #require(
            view.descendant(withAccessibilityIdentifier: "meeting.context") as? NSTextField
        )
        let start = try #require(
            view.descendant(withAccessibilityIdentifier: "meeting.start-time") as? NSTextField
        )
        let countdown = try #require(
            view.descendant(withAccessibilityIdentifier: "meeting.countdown") as? NSTextField
        )

        #expect(view.frame.size == NSSize(width: 376, height: 148))
        #expect(context.font?.pointSize ?? 0 >= 12)
        #expect(start.font?.pointSize ?? 0 >= 12)
        #expect(countdown.font?.pointSize ?? 0 >= 12)
    }

    @Test func meetingPresentationUsesDeepMossMaterialAndMistText() throws {
        // Break caught: the restyled alert reverts to a generic popover whose text loses contrast against the Tepal habitat.
        let view = MeetingPresentationView(
            titles: ["Design review"],
            start: Date(timeIntervalSinceReferenceDate: 250_000),
            appearance: TepalVisualState(
                pose: .ready,
                timerProgress: 0,
                palette: .dewdrop,
                growth: TepalGrowthProfile(completedFocuses: 4),
                reducedMotion: false
            ),
            creatureOnRight: false,
            target: NSObject(),
            dismissAction: #selector(NSObject.description),
            snoozeAction: nil
        )
        defer { view.stopCountdown() }

        let bubble = try #require(view.descendant(withAccessibilityIdentifier: "meeting.bubble") as? NSVisualEffectView)
        let title = try #require(view.descendant(withAccessibilityIdentifier: "meeting.title") as? NSTextField)
        let moonFern = TepalTheme.palette(for: .moonFern)

        #expect(bubble.material == .hudWindow)
        #expect(title.textColor == moonFern.primaryText)
        #expect(view.descendant(withAccessibilityIdentifier: "meeting.snooze") == nil)
    }

    @Test func reducedMotionUsesOneFrameAndFadeWhileDockEdgesMoveOutwardOtherwise() {
        // Break caught: Reduced Motion still translates the alert, or an edge displacement moves it into its Dock.
        let visibleFrame = NSRect(x: 0, y: 0, width: 1_200, height: 900)
        let size = NSSize(width: 376, height: 148)
        let cases: [(DockEdge, CGPoint)] = [
            (.bottom, CGPoint(x: 0, y: 60)),
            (.left, CGPoint(x: 60, y: 0)),
            (.right, CGPoint(x: -60, y: 0)),
        ]

        for (edge, expectedDisplacement) in cases {
            let home = DockGeometry(
                edge: edge,
                homePoint: CGPoint(x: 600, y: 300),
                usedPointer: false
            )
            let moving = ExcursionPresentationPlan.make(
                at: home,
                size: size,
                creatureOnRight: edge == .right,
                reducedMotion: false,
                visibleFrame: visibleFrame
            )
            #expect(moving.destinationFrame.origin.x - moving.startFrame.origin.x == expectedDisplacement.x)
            #expect(moving.destinationFrame.origin.y - moving.startFrame.origin.y == expectedDisplacement.y)
            #expect(!moving.usesFade)

            let reduced = ExcursionPresentationPlan.make(
                at: home,
                size: size,
                creatureOnRight: edge == .right,
                reducedMotion: true,
                visibleFrame: visibleFrame
            )
            #expect(reduced.startFrame == reduced.destinationFrame)
            #expect(reduced.usesFade)
        }
    }

    @Test func combinedMeetingTitleListFillsTheViewportAndRetainsEveryAccessibleTitle() throws {
        // Break caught: assigning a wrapping label directly as a scroll document leaves it at its tiny intrinsic width.
        let titles = [
            "First simultaneous meeting",
            "Second simultaneous meeting",
            "Third simultaneous meeting",
            "Fourth simultaneous meeting",
        ]
        let titleList = MeetingTitleListScrollView(titles: titles)
        titleList.frame = NSRect(x: 0, y: 0, width: 240, height: 52)

        titleList.layoutSubtreeIfNeeded()

        let documentView = try #require(titleList.documentView)
        let accessibilityValue = documentView.accessibilityValue() as? String ?? ""
        #expect(documentView.frame.width == titleList.contentSize.width)
        #expect(documentView.frame.height >= titleList.contentSize.height)
        #expect(titles.allSatisfy(accessibilityValue.contains))
    }

    private func makeMeetingView(reducedMotion: Bool) -> MeetingPresentationView {
        MeetingPresentationView(
            titles: ["Design review"],
            start: Date(timeIntervalSinceReferenceDate: 250_000),
            appearance: TepalVisualState(
                pose: .ready,
                timerProgress: 0.5,
                palette: .moonFern,
                growth: TepalGrowthProfile(completedFocuses: 4),
                reducedMotion: reducedMotion
            ),
            creatureOnRight: false,
            target: NSObject(),
            dismissAction: #selector(NSObject.description),
            snoozeAction: #selector(NSObject.description)
        )
    }
}

@MainActor
private extension NSView {
    func descendant(withAccessibilityIdentifier identifier: String) -> NSView? {
        if accessibilityIdentifier() == identifier { return self }
        return subviews.lazy.compactMap { $0.descendant(withAccessibilityIdentifier: identifier) }.first
    }

    func firstDescendant<View: NSView>(ofType type: View.Type) -> View? {
        if let match = self as? View { return match }
        return subviews.lazy.compactMap { $0.firstDescendant(ofType: type) }.first
    }
}
