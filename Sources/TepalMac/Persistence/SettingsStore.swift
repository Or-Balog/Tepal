import TepalCore
import Foundation

public enum FocusStartDisposition: String, Codable, Equatable, Sendable {
    case interrupted
    case needsOverlapConfirmation
    case legacyUnknown

    public var requiresOverlapConfirmation: Bool {
        switch self {
        case .interrupted:
            false
        case .needsOverlapConfirmation, .legacyUnknown:
            true
        }
    }
}

public struct PomodoroRecovery: Codable, Equatable, Sendable {
    public let snapshot: PomodoroSnapshot
    public let focusStartDisposition: FocusStartDisposition

    public init(
        snapshot: PomodoroSnapshot,
        focusStartDisposition: FocusStartDisposition
    ) {
        self.snapshot = snapshot
        self.focusStartDisposition = focusStartDisposition
    }
}

public final class SettingsStore {
    public static let settingsDidChangeNotification = Notification.Name("Tepal.SettingsStore.settingsDidChange")

    // Persisted keys intentionally retain their original names so upgrades keep user data.
    private enum Key {
        static let settings = "dockpet.v1.settings"
        static let recovery = "dockpet.v1.recovery"
        static let reminderState = "dockpet.v1.reminderState"
        static let all = [settings, recovery, reminderState]
    }

    private struct VersionedRecord<Value: Codable>: Codable {
        let version: Int
        let value: Value
    }

    private static let currentVersion = 1

    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var storedSettings: AppSettings

    public var settings: AppSettings {
        get { storedSettings }
        set {
            let normalized = newValue.normalizedForPersistence()
            guard normalized != storedSettings else { return }
            guard write(normalized, forKey: Key.settings) else { return }
            storedSettings = normalized
            NotificationCenter.default.post(
                name: Self.settingsDidChangeNotification,
                object: self
            )
        }
    }

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        storedSettings = .defaults

        if let decoded: AppSettings = read(forKey: Key.settings) {
            let normalized = decoded.normalizedForPersistence()
            if normalized != decoded {
                _ = write(normalized, forKey: Key.settings)
            }
            storedSettings = normalized
        }
    }

    public func loadRecovery() -> PomodoroSnapshot? {
        loadTimerRecovery()?.snapshot
    }

    public func loadTimerRecovery() -> PomodoroRecovery? {
        guard let data = userDefaults.data(forKey: Key.recovery) else { return nil }

        let recovery: PomodoroRecovery
        if let current = try? decoder.decode(VersionedRecord<PomodoroRecovery>.self, from: data),
           current.version == Self.currentVersion
        {
            recovery = current.value
        } else if let legacy = try? decoder.decode(
            VersionedRecord<PomodoroSnapshot>.self,
            from: data
        ), legacy.version == Self.currentVersion {
            recovery = PomodoroRecovery(
                snapshot: legacy.value,
                focusStartDisposition: Self.legacyDisposition(for: legacy.value)
            )
        } else {
            userDefaults.removeObject(forKey: Key.recovery)
            return nil
        }

        guard PomodoroEngine(
            recovering: recovery.snapshot,
            settings: storedSettings
        ) != nil else {
            userDefaults.removeObject(forKey: Key.recovery)
            return nil
        }
        return recovery
    }

    public func saveRecovery(_ snapshot: PomodoroSnapshot?) {
        saveTimerRecovery(snapshot.map {
            PomodoroRecovery(
                snapshot: $0,
                focusStartDisposition: Self.legacyDisposition(for: $0)
            )
        })
    }

    public func saveTimerRecovery(_ recovery: PomodoroRecovery?) {
        guard let recovery else {
            userDefaults.removeObject(forKey: Key.recovery)
            return
        }
        write(recovery, forKey: Key.recovery)
    }

    public func loadReminderState() -> ReminderState {
        read(forKey: Key.reminderState) ?? ReminderState()
    }

    public func saveReminderState(_ state: ReminderState) {
        write(state, forKey: Key.reminderState)
    }

    public func clearAll() {
        let settingsChanged = storedSettings != .defaults
        for key in Key.all {
            userDefaults.removeObject(forKey: key)
        }
        storedSettings = .defaults
        if settingsChanged {
            NotificationCenter.default.post(
                name: Self.settingsDidChangeNotification,
                object: self
            )
        }
    }

    private func read<Value: Codable>(forKey key: String) -> Value? {
        guard let data = userDefaults.data(forKey: key) else { return nil }

        do {
            let record = try decoder.decode(VersionedRecord<Value>.self, from: data)
            guard record.version == Self.currentVersion else {
                userDefaults.removeObject(forKey: key)
                return nil
            }
            return record.value
        } catch {
            userDefaults.removeObject(forKey: key)
            return nil
        }
    }

    private static func legacyDisposition(
        for snapshot: PomodoroSnapshot
    ) -> FocusStartDisposition {
        snapshot.phase == .focus && snapshot.isPaused
            ? .legacyUnknown
            : .interrupted
    }

    @discardableResult
    private func write<Value: Codable>(_ value: Value, forKey key: String) -> Bool {
        do {
            let record = VersionedRecord(version: Self.currentVersion, value: value)
            userDefaults.set(try encoder.encode(record), forKey: key)
            return true
        } catch {
            return false
        }
    }
}
