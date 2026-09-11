import AppKit
import Foundation

public enum LocalSoundCue: Equatable, Hashable, Sendable {
    case focusStarted
    case focusCompleted
    case meetingReminder
}

enum TepalSoundSynthesis {
    private static let defaultSampleRate = 22_050
    private static let supportedSampleRates = 8_000 ... 192_000

    static func wavData(
        for cue: LocalSoundCue,
        sampleRate: Int = defaultSampleRate
    ) -> Data {
        guard supportedSampleRates.contains(sampleRate) else { return Data() }

        let duration = duration(for: cue)
        let roundedSampleCount = (Double(sampleRate) * duration).rounded()
        guard roundedSampleCount.isFinite,
              let sampleCount = Int(exactly: roundedSampleCount)
        else { return Data() }

        let (payloadByteCount, payloadOverflow) = sampleCount.multipliedReportingOverflow(
            by: MemoryLayout<Int16>.size
        )
        let (byteRate, byteRateOverflow) = sampleRate.multipliedReportingOverflow(
            by: MemoryLayout<Int16>.size
        )
        let (capacity, capacityOverflow) = 44.addingReportingOverflow(payloadByteCount)
        guard !payloadOverflow,
              !byteRateOverflow,
              !capacityOverflow,
              let payloadSize = UInt32(exactly: payloadByteCount),
              let wavSampleRate = UInt32(exactly: sampleRate),
              let wavByteRate = UInt32(exactly: byteRate)
        else { return Data() }

        let (riffChunkSize, riffOverflow) = UInt32(36).addingReportingOverflow(payloadSize)
        guard !riffOverflow else { return Data() }

        let samples = (0..<sampleCount).map { index in
            let time = Double(index) / Double(sampleRate)
            return pcmSample(signal(for: cue, at: time, duration: duration, index: index))
        }
        return waveData(
            samples: samples,
            sampleRate: wavSampleRate,
            byteRate: wavByteRate,
            payloadSize: payloadSize,
            riffChunkSize: riffChunkSize,
            capacity: capacity
        )
    }

    private static func duration(for cue: LocalSoundCue) -> TimeInterval {
        switch cue {
        case .focusStarted: 0.080
        case .focusCompleted: 0.420
        case .meetingReminder: 0.360
        }
    }

    private static func signal(
        for cue: LocalSoundCue,
        at time: TimeInterval,
        duration: TimeInterval,
        index: Int
    ) -> Double {
        switch cue {
        case .focusStarted:
            let fundamental = sin(2 * .pi * 520 * time)
            let woodenOvertone = sin(2 * .pi * 1_040 * time) * 0.22
            return (fundamental + woodenOvertone) * exp(-42 * time) * 0.55

        case .focusCompleted:
            let first = note(frequency: 523, at: time, start: 0, duration: 0.245)
            let second = note(frequency: 659, at: time, start: 0.165, duration: 0.255)
            let textureEnvelope = sin(.pi * min(1, max(0, time / duration)))
            let texture = filteredNoise(at: index) * textureEnvelope * 0.035
            return first * 0.42 + second * 0.46 + texture

        case .meetingReminder:
            let first = note(frequency: 660, at: time, start: 0, duration: 0.205)
            let second = note(frequency: 520, at: time, start: 0.155, duration: 0.205)
            return first * 0.48 + second * 0.44
        }
    }

    private static func note(
        frequency: Double,
        at time: TimeInterval,
        start: TimeInterval,
        duration: TimeInterval
    ) -> Double {
        let localTime = time - start
        guard localTime >= 0, localTime < duration else { return 0 }

        let attack = min(1, localTime / 0.012)
        let release = min(1, (duration - localTime) / 0.070)
        let envelope = attack * release
        let fundamental = sin(2 * .pi * frequency * localTime)
        let softOvertone = sin(2 * .pi * frequency * 2 * localTime) * 0.12
        return (fundamental + softOvertone) * envelope
    }

    private static func filteredNoise(at index: Int) -> Double {
        let current = deterministicNoise(at: index)
        let previous = deterministicNoise(at: max(0, index - 1))
        let prior = deterministicNoise(at: max(0, index - 2))
        return current * 0.25 + previous * 0.50 + prior * 0.25
    }

    private static func deterministicNoise(at index: Int) -> Double {
        var value = UInt32(truncatingIfNeeded: index) &* 1_664_525 &+ 1_013_904_223
        value ^= value >> 15
        return (Double(value) / Double(UInt32.max)) * 2 - 1
    }

    private static func pcmSample(_ signal: Double) -> Int16 {
        let clamped = min(1, max(-1, signal))
        return Int16((clamped * Double(Int16.max)).rounded())
    }

    private static func waveData(
        samples: [Int16],
        sampleRate: UInt32,
        byteRate: UInt32,
        payloadSize: UInt32,
        riffChunkSize: UInt32,
        capacity: Int
    ) -> Data {
        var data = Data()
        data.reserveCapacity(capacity)
        data.append(contentsOf: "RIFF".utf8)
        append(riffChunkSize, to: &data)
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        append(UInt32(16), to: &data)
        append(UInt16(1), to: &data)
        append(UInt16(1), to: &data)
        append(sampleRate, to: &data)
        append(byteRate, to: &data)
        append(UInt16(MemoryLayout<Int16>.size), to: &data)
        append(UInt16(16), to: &data)
        data.append(contentsOf: "data".utf8)
        append(payloadSize, to: &data)
        for sample in samples {
            append(UInt16(bitPattern: sample), to: &data)
        }
        return data
    }

    private static func append(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value >> 16))
        data.append(UInt8(truncatingIfNeeded: value >> 24))
    }
}

@MainActor
public protocol LocalSoundPlaying: AnyObject {
    func play(_ cue: LocalSoundCue)
}

@MainActor
public final class AppKitLocalSoundPlayer: LocalSoundPlaying {
    private var sounds: [LocalSoundCue: NSSound] = [:]

    public init() {
        for cue in [LocalSoundCue.focusStarted, .focusCompleted, .meetingReminder] {
            sounds[cue] = NSSound(data: TepalSoundSynthesis.wavData(for: cue))
        }
    }

    public func play(_ cue: LocalSoundCue) {
        guard let sound = sounds[cue] else { return }
        sound.stop()
        sound.play()
    }
}

@MainActor
public final class SilentLocalSoundPlayer: LocalSoundPlaying {
    public init() {}

    public func play(_ cue: LocalSoundCue) {}
}
