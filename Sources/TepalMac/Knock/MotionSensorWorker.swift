import Foundation
import TepalCore
import OSLog

protocol MotionSampleSource: AnyObject {
    var sampleCount: Int { get }
    func start(onSample: @escaping (Sample) -> Void) throws
    func stop()
}

/// Created, opened, read, and closed on the worker's run-loop thread.
private final class SPUMotionSource: MotionSampleSource {
    private let probe = SPUProbe()
    private let interval = ReportingIntervalTrial()
    var sampleCount: Int { probe.sampleCount }
    func start(onSample: @escaping (Sample) -> Void) throws {
        probe.onSample = onSample
        try probe.start()
        try interval.begin()
    }
    func stop() { interval.restore(); probe.stop() }
}

enum MotionSensorEvent: Sendable {
    case status(String)
    case knock
}

/// Only cancellation/run-loop publication cross threads, protected by condition.
/// All HID, detector, and source lifetime state stays inside run().
final class MotionSensorWorker: @unchecked Sendable {
    private let condition = NSCondition()
    private var started = false
    private var cancelled = false
    private var finished = false
    private var loop: CFRunLoop?
    private let makeSource: @Sendable () -> any MotionSampleSource
    private let emit: @Sendable (MotionSensorEvent) -> Void
    private let log = Logger(subsystem: "com.or-balog.tepal", category: "KnockSensor")

    init(makeSource: @escaping @Sendable () -> any MotionSampleSource = { SPUMotionSource() },
         onEvent: @escaping @Sendable (MotionSensorEvent) -> Void) {
        self.makeSource = makeSource; self.emit = onEvent
    }

    func start() {
        condition.lock()
        guard !started else { condition.unlock(); return }
        started = true
        condition.unlock()
        let thread = Thread { [self] in autoreleasepool { run() } }
        thread.name = "Tepal double-knock sensor"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    /// Wait for same-thread HID cleanup before allowing a replacement worker.
    func stop() {
        condition.lock()
        cancelled = true
        if let loop { CFRunLoopStop(loop); CFRunLoopWakeUp(loop) }
        while started && !finished { condition.wait() }
        condition.unlock()
    }

    private var isCancelled: Bool {
        condition.lock(); defer { condition.unlock() }
        return cancelled
    }

    private func run() {
        condition.lock()
        loop = CFRunLoopGetCurrent()
        condition.unlock()
        defer {
            condition.lock()
            loop = nil; finished = true
            condition.broadcast()
            condition.unlock()
        }
        guard !isCancelled else { return }
        let keepAlive = Port()
        RunLoop.current.add(keepAlive, forMode: .default)
        defer { keepAlive.invalidate() }
        // User explicitly enabled continuous motion sensing. Prevent App Nap while
        // listening, but allow normal display/system sleep and release on every exit.
        let activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Listen for enabled Tepal double-knock gestures")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        let source = makeSource()
        defer { source.stop(); log.info("Sensor cleanup completed") }
        var detector = DoubleKnockDetector()
        do {
            try source.start { [self] sample in
                if detector.process(time: sample.seconds, acceleration: sample.g) {
                    log.info("Double-knock recognized")
                    emit(.knock)
                }
            }
            guard !isCancelled else { return }
            log.info("Sensor started on dedicated run loop")
            emit(.status("Checking the motion stream…"))
            var lastSamples = 0
            var nextCheck = ProcessInfo.processInfo.systemUptime + 3
            while !isCancelled {
                CFRunLoopRunInMode(.defaultMode, 0.25, false)
                guard !isCancelled else { break }
                let now = ProcessInfo.processInfo.systemUptime
                guard now >= nextCheck else { continue }
                let samples = source.sampleCount
                guard samples > lastSamples else {
                    emit(.status("No motion samples. Retry the sensor, or turn double-knock off."))
                    log.error("Motion stream stalled")
                    return
                }
                log.info("Motion samples in interval: \(samples - lastSamples)")
                lastSamples = samples; nextCheck = now + 3
                emit(.status("Listening for a double-knock"))
            }
        } catch {
            emit(.status("Motion sensor unavailable or access denied on this Mac."))
            log.error("Motion source could not start")
        }
    }
}
