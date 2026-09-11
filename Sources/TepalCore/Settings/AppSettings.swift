import Foundation

public enum ReducedMotionPreference: String, Codable, CaseIterable, Sendable {
    case followSystem
    case reduceMotion

    public func resolved(systemSetting: Bool) -> Bool {
        switch self {
        case .followSystem:
            systemSetting
        case .reduceMotion:
            true
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var focusDuration: TimeInterval
    public var shortBreakDuration: TimeInterval
    public var longBreakDuration: TimeInterval
    public var longBreakEvery: Int
    public var autoStartNextPhase: Bool
    public var reminderLead: TimeInterval
    public var snoozeDuration: TimeInterval
    public var calendarLookahead: TimeInterval
    public var calendarRefreshInterval: TimeInterval
    public var doubleKnockEnabled: Bool = false
    public var soundEnabled: Bool
    public var ambientExcursionsEnabled: Bool
    public var meetingAlertsEnabled: Bool
    public var minimumAmbientInterval: TimeInterval
    public var enabledCalendarIDs: Set<String>
    public var confirmedGoogleSourceIDs: Set<String>
    public var petName: String
    public var reducedMotionPreference: ReducedMotionPreference
    public var launchAtLoginEnabled: Bool
    public var onboardingCompleted: Bool
    public var tepalPalette: TepalPaletteID

    public init(
        focusDuration: TimeInterval,
        shortBreakDuration: TimeInterval,
        longBreakDuration: TimeInterval,
        longBreakEvery: Int,
        autoStartNextPhase: Bool,
        reminderLead: TimeInterval,
        snoozeDuration: TimeInterval,
        calendarLookahead: TimeInterval,
        calendarRefreshInterval: TimeInterval,
        soundEnabled: Bool,
        ambientExcursionsEnabled: Bool,
        meetingAlertsEnabled: Bool,
        minimumAmbientInterval: TimeInterval,
        enabledCalendarIDs: Set<String> = [],
        confirmedGoogleSourceIDs: Set<String> = [],
        petName: String = "",
        reducedMotionPreference: ReducedMotionPreference = .followSystem,
        launchAtLoginEnabled: Bool = false,
        onboardingCompleted: Bool = false,
        tepalPalette: TepalPaletteID = .moonFern
    ) {
        self.focusDuration = focusDuration
        self.shortBreakDuration = shortBreakDuration
        self.longBreakDuration = longBreakDuration
        self.longBreakEvery = longBreakEvery
        self.autoStartNextPhase = autoStartNextPhase
        self.reminderLead = reminderLead
        self.snoozeDuration = snoozeDuration
        self.calendarLookahead = calendarLookahead
        self.calendarRefreshInterval = calendarRefreshInterval
        self.soundEnabled = soundEnabled
        self.ambientExcursionsEnabled = ambientExcursionsEnabled
        self.meetingAlertsEnabled = meetingAlertsEnabled
        self.minimumAmbientInterval = minimumAmbientInterval
        self.enabledCalendarIDs = enabledCalendarIDs
        self.confirmedGoogleSourceIDs = confirmedGoogleSourceIDs
        self.petName = petName
        self.reducedMotionPreference = reducedMotionPreference
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.onboardingCompleted = onboardingCompleted
        self.tepalPalette = tepalPalette
    }

    public static let defaults = AppSettings(
        focusDuration: 1_500,
        shortBreakDuration: 300,
        longBreakDuration: 900,
        longBreakEvery: 4,
        autoStartNextPhase: false,
        reminderLead: 600,
        snoozeDuration: 300,
        calendarLookahead: 172_800,
        calendarRefreshInterval: 900,
        soundEnabled: false,
        ambientExcursionsEnabled: true,
        meetingAlertsEnabled: true,
        minimumAmbientInterval: 1_800,
        tepalPalette: .moonFern
    )

    public func normalizedForPersistence() -> AppSettings {
        var normalized = self
        normalized.focusDuration = Self.clamp(
            focusDuration,
            to: 60...7_200,
            fallback: Self.defaults.focusDuration
        )
        normalized.shortBreakDuration = Self.clamp(
            shortBreakDuration,
            to: 60...7_200,
            fallback: Self.defaults.shortBreakDuration
        )
        normalized.longBreakDuration = Self.clamp(
            longBreakDuration,
            to: 60...7_200,
            fallback: Self.defaults.longBreakDuration
        )
        normalized.longBreakEvery = max(1, longBreakEvery)
        normalized.reminderLead = Self.clamp(
            reminderLead,
            to: 60...3_600,
            fallback: Self.defaults.reminderLead
        )
        normalized.snoozeDuration = Self.clamp(
            snoozeDuration,
            to: 60...3_600,
            fallback: Self.defaults.snoozeDuration
        )
        normalized.calendarLookahead = Self.clamp(
            calendarLookahead,
            to: 3_600...604_800,
            fallback: Self.defaults.calendarLookahead
        )
        normalized.calendarRefreshInterval = Self.clamp(
            calendarRefreshInterval,
            to: 60...86_400,
            fallback: Self.defaults.calendarRefreshInterval
        )
        normalized.minimumAmbientInterval = minimumAmbientInterval.isFinite
            ? max(1_800, minimumAmbientInterval)
            : Self.defaults.minimumAmbientInterval
        normalized.enabledCalendarIDs = Self.normalizedIdentifiers(enabledCalendarIDs)
        normalized.confirmedGoogleSourceIDs = Self.normalizedIdentifiers(confirmedGoogleSourceIDs)
        if normalized.confirmedGoogleSourceIDs.isEmpty {
            normalized.enabledCalendarIDs = []
        }
        normalized.petName = String(
            petName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32)
        )
        return normalized
    }

    private enum CodingKeys: String, CodingKey {
        case focusDuration
        case shortBreakDuration
        case longBreakDuration
        case longBreakEvery
        case autoStartNextPhase
        case reminderLead
        case snoozeDuration
        case calendarLookahead
        case calendarRefreshInterval
        case doubleKnockEnabled
        case soundEnabled
        case ambientExcursionsEnabled
        case meetingAlertsEnabled
        case minimumAmbientInterval
        case enabledCalendarIDs
        case confirmedGoogleSourceIDs
        case petName
        case reducedMotionPreference
        case launchAtLoginEnabled
        case onboardingCompleted
        case tepalPalette = "moonmossPalette" // Preserve palettes saved before the Tepal rename.
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.defaults
        focusDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .focusDuration)
            ?? defaults.focusDuration
        shortBreakDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .shortBreakDuration)
            ?? defaults.shortBreakDuration
        longBreakDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .longBreakDuration)
            ?? defaults.longBreakDuration
        longBreakEvery = try container.decodeIfPresent(Int.self, forKey: .longBreakEvery)
            ?? defaults.longBreakEvery
        autoStartNextPhase = try container.decodeIfPresent(Bool.self, forKey: .autoStartNextPhase)
            ?? defaults.autoStartNextPhase
        reminderLead = try container.decodeIfPresent(TimeInterval.self, forKey: .reminderLead)
            ?? defaults.reminderLead
        snoozeDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .snoozeDuration)
            ?? defaults.snoozeDuration
        calendarLookahead = try container.decodeIfPresent(TimeInterval.self, forKey: .calendarLookahead)
            ?? defaults.calendarLookahead
        calendarRefreshInterval = try container.decodeIfPresent(
            TimeInterval.self,
            forKey: .calendarRefreshInterval
        ) ?? defaults.calendarRefreshInterval
        doubleKnockEnabled = try container.decodeIfPresent(Bool.self, forKey: .doubleKnockEnabled) ?? false
        soundEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled)
            ?? defaults.soundEnabled
        ambientExcursionsEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .ambientExcursionsEnabled
        ) ?? defaults.ambientExcursionsEnabled
        meetingAlertsEnabled = try container.decodeIfPresent(Bool.self, forKey: .meetingAlertsEnabled)
            ?? defaults.meetingAlertsEnabled
        minimumAmbientInterval = try container.decodeIfPresent(
            TimeInterval.self,
            forKey: .minimumAmbientInterval
        ) ?? defaults.minimumAmbientInterval
        enabledCalendarIDs = try container.decodeIfPresent(Set<String>.self, forKey: .enabledCalendarIDs)
            ?? defaults.enabledCalendarIDs
        confirmedGoogleSourceIDs = try container.decodeIfPresent(
            Set<String>.self,
            forKey: .confirmedGoogleSourceIDs
        ) ?? defaults.confirmedGoogleSourceIDs
        petName = try container.decodeIfPresent(String.self, forKey: .petName)
            ?? defaults.petName
        reducedMotionPreference = try container.decodeIfPresent(
            ReducedMotionPreference.self,
            forKey: .reducedMotionPreference
        ) ?? defaults.reducedMotionPreference
        launchAtLoginEnabled = try container.decodeIfPresent(Bool.self, forKey: .launchAtLoginEnabled)
            ?? defaults.launchAtLoginEnabled
        onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted)
            ?? defaults.onboardingCompleted
        do {
            tepalPalette = try container.decodeIfPresent(
                TepalPaletteID.self,
                forKey: .tepalPalette
            ) ?? defaults.tepalPalette
        } catch {
            tepalPalette = defaults.tepalPalette
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(focusDuration, forKey: .focusDuration)
        try container.encode(shortBreakDuration, forKey: .shortBreakDuration)
        try container.encode(longBreakDuration, forKey: .longBreakDuration)
        try container.encode(longBreakEvery, forKey: .longBreakEvery)
        try container.encode(autoStartNextPhase, forKey: .autoStartNextPhase)
        try container.encode(reminderLead, forKey: .reminderLead)
        try container.encode(snoozeDuration, forKey: .snoozeDuration)
        try container.encode(calendarLookahead, forKey: .calendarLookahead)
        try container.encode(calendarRefreshInterval, forKey: .calendarRefreshInterval)
        try container.encode(doubleKnockEnabled, forKey: .doubleKnockEnabled)
        try container.encode(soundEnabled, forKey: .soundEnabled)
        try container.encode(ambientExcursionsEnabled, forKey: .ambientExcursionsEnabled)
        try container.encode(meetingAlertsEnabled, forKey: .meetingAlertsEnabled)
        try container.encode(minimumAmbientInterval, forKey: .minimumAmbientInterval)
        try container.encode(enabledCalendarIDs, forKey: .enabledCalendarIDs)
        try container.encode(confirmedGoogleSourceIDs, forKey: .confirmedGoogleSourceIDs)
        try container.encode(petName, forKey: .petName)
        try container.encode(reducedMotionPreference, forKey: .reducedMotionPreference)
        try container.encode(launchAtLoginEnabled, forKey: .launchAtLoginEnabled)
        try container.encode(onboardingCompleted, forKey: .onboardingCompleted)
        try container.encode(tepalPalette, forKey: .tepalPalette)
    }

    private static func normalizedIdentifiers(_ values: Set<String>) -> Set<String> {
        Set(values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        })
    }

    private static func clamp(
        _ value: TimeInterval,
        to range: ClosedRange<TimeInterval>,
        fallback: TimeInterval
    ) -> TimeInterval {
        guard value.isFinite else { return fallback }
        return min(range.upperBound, max(range.lowerBound, value))
    }
}
