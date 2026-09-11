// In-process sensor component. No calendar or input-event access.
// Protocol evidence: https://github.com/olvvier/apple-silicon-accelerometer
import Foundation
import IOKit
import IOKit.hid
import Darwin

struct Sample {
    let seconds: Double
    let g: SIMD3<Double>
}

enum ProbeError: Error {
    case registry(IOReturn), unavailable, open(IOReturn)
}

final class SPUProbe {
    private var device: IOHIDDevice?
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
    private var loop: CFRunLoop?
    private var timebase = mach_timebase_info_data_t()
    private(set) var sampleCount = 0
    var onSample: (Sample) -> Void = { _ in }

    init() { mach_timebase_info(&timebase) }
    deinit { stop(); buffer.deallocate() }

    // Call start/stop on the same thread that owns the run loop.
    func start() throws {
        guard device == nil else { return }
        var iterator: io_iterator_t = 0
        let status = IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("AppleSPUHIDDevice"), &iterator)
        guard status == KERN_SUCCESS else { throw ProbeError.registry(status) }
        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }
            func integer(_ key: String) -> Int? {
                IORegistryEntryCreateCFProperty(service, key as CFString,
                    kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
            }
            guard integer("PrimaryUsagePage") == 0xFF00,
                  integer("PrimaryUsage") == 3,
                  integer("MaxInputReportSize") == 22 else { continue }
            guard let hid = IOHIDDeviceCreate(kCFAllocatorDefault, service) else { continue }
            let opened = IOHIDDeviceOpen(hid, IOOptionBits(kIOHIDOptionsTypeNone))
            guard opened == kIOReturnSuccess else { throw ProbeError.open(opened) }
            device = hid
            loop = CFRunLoopGetCurrent()
            IOHIDDeviceRegisterInputReportWithTimeStampCallback(
                hid, buffer, 4096, { context, result, _, type, _, report, length, stamp in
                    guard let context, result == kIOReturnSuccess,
                          type == kIOHIDReportTypeInput, length == 22 else { return }
                    let owner = Unmanaged<SPUProbe>.fromOpaque(context).takeUnretainedValue()
                    owner.receive(report, stamp: stamp)
                }, Unmanaged.passUnretained(self).toOpaque())
            IOHIDDeviceScheduleWithRunLoop(hid, loop!, CFRunLoopMode.commonModes.rawValue)
            return
        }
        throw ProbeError.unavailable
    }

    func stop() {
        guard let hid = device else { return }
        if let loop {
            IOHIDDeviceUnscheduleFromRunLoop(hid, loop, CFRunLoopMode.commonModes.rawValue)
        }
        IOHIDDeviceRegisterInputReportWithTimeStampCallback(hid, buffer, 4096, nil, nil)
        IOHIDDeviceClose(hid, IOOptionBits(kIOHIDOptionsTypeNone))
        device = nil
        loop = nil
    }

    private func receive(_ bytes: UnsafePointer<UInt8>, stamp: UInt64) {
        // Explicit byte assembly avoids unaligned Int32 loads at offsets 6/10/14.
        func axis(_ offset: Int) -> Double {
            var bits: UInt32 = 0
            for i in 0..<4 { bits |= UInt32(bytes[offset + i]) << (8 * i) }
            return Double(Int32(bitPattern: bits)) / 65536.0
        }
        let seconds = Double(stamp) * Double(timebase.numer) / Double(timebase.denom) * 1e-9
        sampleCount += 1
        onSample(Sample(seconds: seconds, g: SIMD3(axis(6), axis(10), axis(14))))
    }
}

// Optional reversible trial: only the existing interval property is changed.
// Reporting/power properties that cannot be read back are intentionally untouched.
// The value to restore is recorded on disk before the change, so a crash or a
// forced quit no longer strands the driver at the raised rate.
// See SensorReportIntervalGuard.
final class ReportingIntervalTrial {
    private var driver: io_service_t = 0
    private var didChangeInterval = false

    func begin() throws {
        // Repair anything an earlier run left behind before taking a new reading,
        // otherwise the raised rate would be recorded as the value to restore.
        SensorReportIntervalGuard.restorePendingChange()

        guard let service = SensorReportIntervalGuard.copyDriverService() else {
            throw ProbeError.unavailable
        }
        driver = service

        // Never change a value that cannot be read back and put right again.
        guard let previous = IORegistryEntryCreateCFProperty(
            driver,
            SensorReportIntervalGuard.propertyKey as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? Int else { throw ProbeError.unavailable }

        _ = SensorReportIntervalGuard.installTerminationHandlers
        SensorReportIntervalGuard.recordPendingChange(previousInterval: previous)

        let result = IORegistryEntrySetCFProperty(
            driver,
            SensorReportIntervalGuard.propertyKey as CFString,
            NSNumber(value: 1000)
        )
        guard result == kIOReturnSuccess else {
            SensorReportIntervalGuard.clearPendingChange()
            throw ProbeError.registry(result)
        }
        didChangeInterval = true
    }

    func restore() {
        if driver != 0 {
            IOObjectRelease(driver)
            driver = 0
        }
        guard didChangeInterval else { return }
        didChangeInterval = false
        SensorReportIntervalGuard.restorePendingChange()
    }

    deinit { restore() }
}
