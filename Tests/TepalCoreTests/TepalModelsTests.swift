import TepalCore
import Testing

struct TepalModelsTests {
    @Test func paletteIdentifiersAreStableAndComplete() {
        #expect(TepalPaletteID.allCases == [
            .moonFern, .twilightPlum, .dewdrop,
            .pollenGold, .emberMoss, .frostBloom,
        ])
        #expect(TepalPaletteID.moonFern.rawValue == "moonFern")
        #expect(TepalPaletteID.frostBloom.rawValue == "frostBloom")
    }

    @Test(arguments: [
        (0, TepalGrowthTier.seedling),
        (1, .glowing),
        (4, .sprouted),
        (12, .flourishing),
        (25, .mature),
    ])
    func growthTiersFollowDocumentedMilestones(count: Int, tier: TepalGrowthTier) {
        #expect(TepalGrowthProfile(completedFocuses: count).tier == tier)
    }

    @Test func palettesUnlockWithoutChangingSelection() {
        #expect(TepalGrowthProfile(completedFocuses: 0).availablePalettes == [
            .moonFern, .twilightPlum, .dewdrop,
        ])
        #expect(TepalGrowthProfile(completedFocuses: 12).availablePalettes == [
            .moonFern, .twilightPlum, .dewdrop, .pollenGold, .emberMoss,
        ])
    }

    @Test func visualPolicyMapsEveryPetStateAndClampsProgress() {
        let state = TepalPresentationPolicy.make(
            petState: .meetingAlert,
            isTimerPaused: false,
            timerProgress: 2,
            palette: .moonFern,
            completedFocuses: 4,
            reducedMotion: true
        )
        #expect(state.pose == .meetingAttentive)
        #expect(state.timerProgress == 1)
        #expect(state.growth.tier == .sprouted)
        #expect(state.reducedMotion)
    }

    @Test func presentationMapsPetStatesToPoses() {
        let expected: [(PetState, TepalPose)] = [
            (.idle, .ready),
            (.focus, .keepingWatch),
            (.rest, .resting),
            (.meetingAlert, .meetingAttentive),
            (.reward, .completionBloom),
            (.excursion, .walking),
        ]
        for (petState, pose) in expected {
            #expect(TepalPresentationPolicy.make(
                petState: petState,
                isTimerPaused: false,
                timerProgress: 0.5,
                palette: .dewdrop,
                completedFocuses: 0,
                reducedMotion: false
            ).pose == pose)
        }
        #expect(TepalPresentationPolicy.make(
            petState: .focus,
            isTimerPaused: true,
            timerProgress: 0.5,
            palette: .dewdrop,
            completedFocuses: 0,
            reducedMotion: false
        ).pose == .pausedCurious)
    }

    @Test func reducedMotionStopsEveryDecorativeFrameLoop() {
        for pose in TepalPose.allCases {
            #expect(TepalMotionPolicy.framesPerSecond(for: pose, reducedMotion: true) == 0)
        }
    }

    @Test func attentionHierarchyIsStable() {
        // Break caught: a low-priority passive pose can outrank a meeting or completion reaction.
        #expect(TepalMotionPolicy.attentionLevel(for: .keepingWatch) == 0)
        #expect(TepalMotionPolicy.attentionLevel(for: .ready) == 1)
        #expect(TepalMotionPolicy.attentionLevel(for: .meetingAttentive) == 2)
        #expect(TepalMotionPolicy.attentionLevel(for: .completionBloom) == 3)
    }

    @Test func normalReadyCadenceIncludesRareBlinkAndLeafEarSwayFrames() {
        // Break caught: the native terrarium consumes an FPS policy but always renders frame zero.
        let frames = (0..<64).map {
            TepalMotionPolicy.frame(for: .ready, frameIndex: $0, reducedMotion: false)
        }

        #expect(frames.filter { $0.eyeOpen < 1 }.count == 2)
        #expect(Set(frames.map(\.leafSway)).count >= 3)
        #expect(frames.allSatisfy { abs($0.leafSway) <= 1 })
    }

    @Test func semanticInterruptionAndReducedMotionAlwaysReplaceCadenceWithASettledFrame() {
        let active = TepalMotionPolicy.frame(
            for: .ready,
            frameIndex: 1,
            reducedMotion: false
        )
        let interrupted = TepalMotionPolicy.frame(
            for: .meetingAttentive,
            frameIndex: 1,
            reducedMotion: false
        )

        #expect(active != .settled)
        #expect(interrupted == .settled)
        for pose in TepalPose.allCases {
            for frameIndex in [0, 1, 31, 63] {
                #expect(TepalMotionPolicy.frame(
                    for: pose,
                    frameIndex: frameIndex,
                    reducedMotion: true
                ) == .settled)
            }
        }
    }

    @Test func focusedAttentionKeepsLeafSwayQuieterThanTheReadyHabitat() {
        let readySway = (0..<4).map {
            abs(TepalMotionPolicy.frame(for: .ready, frameIndex: $0, reducedMotion: false).leafSway)
        }.max() ?? 0
        let focusedSway = (0..<4).map {
            abs(TepalMotionPolicy.frame(for: .keepingWatch, frameIndex: $0, reducedMotion: false).leafSway)
        }.max() ?? 0

        #expect(focusedSway > 0)
        #expect(focusedSway < readySway)
    }

    @Test func everyBlinkCadenceRemainsEvenAcrossTheBoundedFrameCycle() {
        let blinkIndices = (0..<1_000).filter {
            TepalMotionPolicy.frame(
                for: .pausedCurious,
                frameIndex: $0,
                reducedMotion: false
            ).eyeOpen < 1
        }

        #expect(zip(blinkIndices, blinkIndices.dropFirst()).allSatisfy { next in
            next.1 - next.0 == 40
        })
    }
}
