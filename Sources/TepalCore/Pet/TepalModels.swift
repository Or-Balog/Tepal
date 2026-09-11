public enum TepalPaletteID: String, Codable, CaseIterable, Hashable, Sendable {
    case moonFern
    case twilightPlum
    case dewdrop
    case pollenGold
    case emberMoss
    case frostBloom
}

public enum TepalGrowthTier: String, CaseIterable, Equatable, Sendable {
    case seedling, glowing, sprouted, flourishing, mature
}

public enum TepalPose: String, CaseIterable, Equatable, Sendable {
    case ready, preparingFocus, keepingWatch, pausedCurious
    case resting, meetingAttentive, completionBloom, walking, staticFallback
}

public struct TepalGrowthProfile: Equatable, Sendable {
    public let completedFocuses: Int
    public let tier: TepalGrowthTier
    public let availablePalettes: [TepalPaletteID]
    public let nextMilestone: Int?
    public let progressToNextMilestone: Double

    public init(completedFocuses: Int) {
        let count = max(0, completedFocuses)
        self.completedFocuses = count
        if count >= 25 { tier = .mature }
        else if count >= 12 { tier = .flourishing }
        else if count >= 4 { tier = .sprouted }
        else if count >= 1 { tier = .glowing }
        else { tier = .seedling }

        switch tier {
        case .seedling, .glowing:
            availablePalettes = [.moonFern, .twilightPlum, .dewdrop]
        case .sprouted:
            availablePalettes = [.moonFern, .twilightPlum, .dewdrop, .pollenGold]
        case .flourishing:
            availablePalettes = [.moonFern, .twilightPlum, .dewdrop, .pollenGold, .emberMoss]
        case .mature:
            availablePalettes = TepalPaletteID.allCases
        }

        switch count {
        case 0..<1:
            nextMilestone = 1
            progressToNextMilestone = Double(count)
        case 1..<4:
            nextMilestone = 4
            progressToNextMilestone = Double(count - 1) / 3
        case 4..<12:
            nextMilestone = 12
            progressToNextMilestone = Double(count - 4) / 8
        case 12..<25:
            nextMilestone = 25
            progressToNextMilestone = Double(count - 12) / 13
        default:
            nextMilestone = nil
            progressToNextMilestone = 1
        }
    }
}

public struct TepalVisualState: Equatable, Sendable {
    public let pose: TepalPose
    public let timerProgress: Double
    public let palette: TepalPaletteID
    public let growth: TepalGrowthProfile
    public let reducedMotion: Bool

    public func replacingPose(_ pose: TepalPose) -> TepalVisualState {
        TepalVisualState(pose: pose, timerProgress: timerProgress, palette: palette, growth: growth, reducedMotion: reducedMotion)
    }

    public init(pose: TepalPose, timerProgress: Double, palette: TepalPaletteID, growth: TepalGrowthProfile, reducedMotion: Bool) {
        self.pose = pose
        self.timerProgress = timerProgress
        self.palette = palette
        self.growth = growth
        self.reducedMotion = reducedMotion
    }
}

public enum TepalPresentationPolicy {
    public static func make(
        petState: PetState,
        isTimerPaused: Bool,
        timerProgress: Double,
        palette: TepalPaletteID,
        completedFocuses: Int,
        reducedMotion: Bool
    ) -> TepalVisualState {
        let pose: TepalPose
        switch petState {
        case .idle: pose = .ready
        case .focus: pose = isTimerPaused ? .pausedCurious : .keepingWatch
        case .rest: pose = .resting
        case .meetingAlert: pose = .meetingAttentive
        case .reward: pose = .completionBloom
        case .excursion: pose = .walking
        }
        return TepalVisualState(
            pose: pose,
            timerProgress: min(1, max(0, timerProgress)),
            palette: palette,
            growth: TepalGrowthProfile(completedFocuses: completedFocuses),
            reducedMotion: reducedMotion
        )
    }
}

public struct TepalMotionFrame: Equatable, Sendable {
    public let eyeOpen: Double
    public let leafSway: Double

    public init(eyeOpen: Double, leafSway: Double) {
        self.eyeOpen = eyeOpen
        self.leafSway = leafSway
    }

    public static let settled = TepalMotionFrame(eyeOpen: 1, leafSway: 0)
}

public enum TepalMotionPolicy {
    public static func attentionLevel(for pose: TepalPose) -> Int {
        switch pose {
        case .preparingFocus, .keepingWatch, .staticFallback: 0
        case .ready, .pausedCurious, .resting, .walking: 1
        case .meetingAttentive: 2
        case .completionBloom: 3
        }
    }

    public static func framesPerSecond(for pose: TepalPose, reducedMotion: Bool) -> Double {
        guard !reducedMotion else { return 0 }
        switch pose {
        case .ready: return 2
        case .keepingWatch, .resting, .preparingFocus, .pausedCurious: return 1
        case .completionBloom: return 10
        case .walking: return 8
        case .meetingAttentive, .staticFallback: return 0
        }
    }

    public static func frame(
        for pose: TepalPose,
        frameIndex: Int,
        reducedMotion: Bool
    ) -> TepalMotionFrame {
        guard framesPerSecond(for: pose, reducedMotion: reducedMotion) > 0 else {
            return .settled
        }

        // 960 is the least common multiple of every blink period and the four-frame
        // leaf cycle, so bounding the integer never introduces a cadence discontinuity.
        let normalizedIndex = ((frameIndex % 960) + 960) % 960
        let leafPhases = [0.0, 1.0, 0.0, -1.0]
        let leafSway = leafPhases[normalizedIndex % leafPhases.count] * leafSwayAmplitude(for: pose)
        let eyeOpen: Double
        if let period = blinkPeriod(for: pose), normalizedIndex % period == period - 1 {
            eyeOpen = 0.12
        } else {
            eyeOpen = 1
        }
        return TepalMotionFrame(eyeOpen: eyeOpen, leafSway: leafSway)
    }

    private static func leafSwayAmplitude(for pose: TepalPose) -> Double {
        switch pose {
        case .ready: 1
        case .preparingFocus: 0.15
        case .keepingWatch: 0.20
        case .pausedCurious: 0.70
        case .resting: 0.35
        case .completionBloom: 0.80
        case .walking: 1
        case .meetingAttentive, .staticFallback: 0
        }
    }

    private static func blinkPeriod(for pose: TepalPose) -> Int? {
        switch pose {
        case .ready: 32
        case .keepingWatch: 48
        case .pausedCurious: 40
        case .resting: 64
        case .preparingFocus, .meetingAttentive, .completionBloom, .walking, .staticFallback: nil
        }
    }
}
