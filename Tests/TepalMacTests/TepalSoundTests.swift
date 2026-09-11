import Foundation
import Testing
@testable import TepalMac

struct TepalSoundTests {
    private let sampleRate = 22_050

    @Test func everyCueProducesAValidBoundedMonoPCMWave() throws {
        // Break caught: synthesized feedback has a malformed WAV header, wrong sample layout, or an unbounded duration.
        let expectedSampleCounts: [LocalSoundCue: Int] = [
            .focusStarted: 1_764,
            .focusCompleted: 9_261,
            .meetingReminder: 7_938,
        ]

        for cue in [LocalSoundCue.focusStarted, .focusCompleted, .meetingReminder] {
            let data = TepalSoundSynthesis.wavData(for: cue, sampleRate: sampleRate)
            let expectedSamples = try #require(expectedSampleCounts[cue])

            #expect(String(data: data.prefix(4), encoding: .ascii) == "RIFF")
            #expect(String(data: data[8..<12], encoding: .ascii) == "WAVE")
            #expect(String(data: data[12..<16], encoding: .ascii) == "fmt ")
            #expect(String(data: data[36..<40], encoding: .ascii) == "data")
            #expect(littleEndianUInt32(data, at: 4) == UInt32(data.count - 8))
            #expect(littleEndianUInt32(data, at: 16) == 16)
            #expect(littleEndianUInt16(data, at: 20) == 1)
            #expect(littleEndianUInt16(data, at: 22) == 1)
            #expect(littleEndianUInt32(data, at: 24) == UInt32(sampleRate))
            #expect(littleEndianUInt32(data, at: 28) == UInt32(sampleRate * 2))
            #expect(littleEndianUInt16(data, at: 32) == 2)
            #expect(littleEndianUInt16(data, at: 34) == 16)
            #expect(littleEndianUInt32(data, at: 40) == UInt32(expectedSamples * 2))
            #expect(data.count == 44 + expectedSamples * 2)
            #expect(Double(expectedSamples) / Double(sampleRate) < 1)

            let samples = pcmSamples(in: data)
            #expect(samples.contains { $0 > 0 })
            #expect(samples.contains { $0 < 0 })
        }
    }

    @Test func cuePayloadsAreDistinctAndDeterministic() {
        // Break caught: cues collapse to the same generic beep or use runtime randomness that changes the local sound language.
        let firstCompletion = TepalSoundSynthesis.wavData(
            for: .focusCompleted,
            sampleRate: sampleRate
        )
        let secondCompletion = TepalSoundSynthesis.wavData(
            for: .focusCompleted,
            sampleRate: sampleRate
        )
        let payloads = [LocalSoundCue.focusStarted, .focusCompleted, .meetingReminder].map {
            TepalSoundSynthesis.wavData(for: $0, sampleRate: sampleRate).dropFirst(44)
        }

        #expect(firstCompletion == secondCompletion)
        #expect(Set(payloads).count == 3)
    }

    @Test func samplesUseClampedLittleEndianSigned16BitOutput() throws {
        // Break caught: floating-point synthesis wraps on conversion or writes host-order PCM bytes.
        let start = TepalSoundSynthesis.wavData(for: .focusStarted, sampleRate: sampleRate)
        let data = TepalSoundSynthesis.wavData(for: .focusCompleted, sampleRate: sampleRate)
        let samples = pcmSamples(in: data)
        let peak = try #require(samples.map { abs(Int($0)) }.max())

        #expect(peak > 1_000)
        #expect(peak <= Int(Int16.max))
        #expect(Array(start[44..<60]) == [
            0, 0, 227, 14, 25, 29, 15, 42,
            69, 53, 88, 62, 6, 69, 50, 73,
        ])
        let firstNonzeroIndex = try #require(samples.firstIndex(where: { $0 != 0 }))
        let byteOffset = 44 + firstNonzeroIndex * 2
        let reconstructed = Int16(bitPattern:
            UInt16(data[byteOffset]) | (UInt16(data[byteOffset + 1]) << 8)
        )
        #expect(reconstructed == samples[firstNonzeroIndex])
    }

    @Test func unsupportedSampleRatesAreRejectedBeforeSynthesis() {
        // Break caught: an out-of-contract positive rate reaches allocation and unchecked RIFF integer narrowing.
        #expect(TepalSoundSynthesis.wavData(
            for: .focusStarted,
            sampleRate: 1_000_000
        ).isEmpty)
        #expect(TepalSoundSynthesis.wavData(
            for: .meetingReminder,
            sampleRate: 192_001
        ).isEmpty)
        #expect(TepalSoundSynthesis.wavData(
            for: .focusCompleted,
            sampleRate: Int.max
        ).isEmpty)

        let maximumSupported = TepalSoundSynthesis.wavData(
            for: .focusStarted,
            sampleRate: 192_000
        )
        #expect(!maximumSupported.isEmpty)
        #expect(littleEndianUInt32(maximumSupported, at: 24) == 192_000)
        #expect(littleEndianUInt32(maximumSupported, at: 28) == 384_000)
    }

    private func littleEndianUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func littleEndianUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private func pcmSamples(in data: Data) -> [Int16] {
        stride(from: 44, to: data.count, by: 2).map { offset in
            Int16(bitPattern:
                UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            )
        }
    }
}
