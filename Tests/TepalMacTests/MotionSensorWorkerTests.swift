import Foundation
import Testing
@testable import TepalMac

struct MotionSensorWorkerTests {
    @MainActor
    @Test func detectsWhileMainThreadIsBlockedAndCleansUpOnSourceThread() {
        let observations = WorkerObservations()
        let recognized = DispatchSemaphore(value: 0)
        let worker = MotionSensorWorker(makeSource: { TestMotionSource(observations: observations) }) { event in
            if case .knock = event { recognized.signal() }
        }
        worker.start()
        // Deliberately block the UI thread. Detection must finish on its own run loop.
        let result = recognized.wait(timeout: .now() + 2)
        worker.stop()
        #expect(result == .success)
        let resultState = observations.snapshot()
        #expect(resultState.startedOffMain)
        #expect(resultState.stoppedOnSourceThread)
        #expect(resultState.stopCount == 1)
        worker.stop()
        #expect(observations.snapshot().stopCount == 1)
    }

    @Test func failedSourceStillClosesOnItsOwningThread() {
        let observations = WorkerObservations()
        let failure = DispatchSemaphore(value: 0)
        let worker = MotionSensorWorker(makeSource: { TestMotionSource(observations: observations, shouldFail: true) }) { event in
            if case .status(let message) = event, message.contains("unavailable") { failure.signal() }
        }
        worker.start()
        #expect(failure.wait(timeout: .now() + 2) == .success)
        worker.stop()
        #expect(observations.snapshot().stoppedOnSourceThread)
        #expect(observations.snapshot().stopCount == 1)
    }
}

private final class WorkerObservations: @unchecked Sendable {
    struct Snapshot {
        var startedOffMain = false
        var stoppedOnSourceThread = false
        var stopCount = 0
    }
    private let lock = NSLock()
    private var state = Snapshot()
    private var sourceThread: ObjectIdentifier?
    func started() {
        lock.lock(); defer { lock.unlock() }
        state.startedOffMain = !Thread.isMainThread
        sourceThread = ObjectIdentifier(Thread.current)
    }
    func stopped() {
        lock.lock(); defer { lock.unlock() }
        state.stoppedOnSourceThread = sourceThread == ObjectIdentifier(Thread.current)
        state.stopCount += 1
    }
    func snapshot() -> Snapshot { lock.lock(); defer { lock.unlock() }; return state }
}

private final class TestMotionSource: MotionSampleSource {
    enum Failure: Error { case unavailable }
    let observations: WorkerObservations
    let shouldFail: Bool
    private(set) var sampleCount = 0
    init(observations: WorkerObservations, shouldFail: Bool = false) {
        self.observations = observations; self.shouldFail = shouldFail
    }
    func start(onSample: @escaping (Sample) -> Void) throws {
        observations.started()
        if shouldFail { throw Failure.unavailable }
        for index in 0..<1600 {
            let time = Double(index) / 800
            let energy = [1.0, 1.3].reduce(0.0) { $0 + 0.06 * exp(-pow((time - $1) / 0.007, 2)) }
            sampleCount += 1
            onSample(Sample(seconds: time, g: SIMD3(energy, 0, 1)))
        }
    }
    func stop() { observations.stopped() }
}
