import Darwin
import Dispatch
import Foundation
import IOKit

/// The optional double-knock sensor raises the SPU HID driver's reporting rate, and
/// that change outlives this process. The previous value is therefore written to
/// disk *before* the change is made, so an abrupt exit can be repaired rather than
/// leaving the driver reporting faster than the system expects.
///
/// Three layers cover the exit paths: an orderly `restore()`, termination handlers
/// for ordinary exits and `SIGTERM`/`SIGINT`/`SIGHUP`, and the recorded value on
/// disk for a crash or forced termination, replayed at the next launch.
public enum SensorReportIntervalGuard {
    static let driverServiceName = "AppleSPUHIDDriver"
    static let propertyKey = "ReportInterval"
    // Key prefix intentionally matches the other persisted records.
    static let defaultsKey = "dockpet.v1.pendingSensorReportInterval"

    private static let lock = NSLock()
    private nonisolated(unsafe) static var signalSources: [DispatchSourceSignal] = []

    /// Restores an interval left behind by this or an earlier run. Safe to call at
    /// any time and from any thread; does nothing when no change is pending.
    public static func restorePendingChange(defaults: UserDefaults = .standard) {
        lock.lock()
        defer { lock.unlock() }

        guard let previous = defaults.object(forKey: defaultsKey) as? Int else { return }
        guard let driver = copyDriverService() else { return }
        defer { IOObjectRelease(driver) }

        let result = IORegistryEntrySetCFProperty(
            driver,
            propertyKey as CFString,
            NSNumber(value: previous)
        )
        guard result == kIOReturnSuccess else {
            FileHandle.standardError.write(Data("Sensor interval restoration failed\n".utf8))
            return
        }
        defaults.removeObject(forKey: defaultsKey)
    }

    /// Records the value to put back before the driver is changed.
    static func recordPendingChange(previousInterval: Int, defaults: UserDefaults = .standard) {
        defaults.set(previousInterval, forKey: defaultsKey)
        // Flush now: the driver is about to change and the note must survive a crash
        // that happens immediately afterwards.
        defaults.synchronize()
    }

    static func clearPendingChange(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }

    /// Installed once, lazily, the first time the interval is actually changed.
    static let installTerminationHandlers: Bool = {
        atexit { SensorReportIntervalGuard.restorePendingChange() }

        for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
            // The default action would kill the process before any cleanup runs.
            // A dispatch source observes the signal outside signal-handler context,
            // where IOKit calls are safe.
            _ = signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(
                signal: signalNumber,
                queue: .global(qos: .userInitiated)
            )
            source.setEventHandler {
                restorePendingChange()
                // Then die exactly as the process would have without this handler.
                _ = signal(signalNumber, SIG_DFL)
                raise(signalNumber)
            }
            source.resume()
            signalSources.append(source)
        }
        return true
    }()

    /// The SPU HID driver entry, or `nil` when this Mac has none.
    /// The caller owns the returned service and must release it.
    static func copyDriverService() -> io_service_t? {
        var iterator: io_iterator_t = 0
        let status = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching(driverServiceName),
            &iterator
        )
        guard status == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { return nil }
            func number(_ key: String) -> Int? {
                IORegistryEntryCreateCFProperty(
                    service, key as CFString, kCFAllocatorDefault, 0
                )?.takeRetainedValue() as? Int
            }
            if number("PrimaryUsagePage") == 0xFF00, number("PrimaryUsage") == 3 {
                return service
            }
            IOObjectRelease(service)
        }
    }
}
