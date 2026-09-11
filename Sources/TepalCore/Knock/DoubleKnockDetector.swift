import Foundation

/// All state is confined to the sample-processing thread.
public struct DoubleKnockDetector: Sendable {
    private var gravity: SIMD3<Double>?
    private var lastTime: Double?
    private var origin = 0.0
    private var block = 0
    private var squareSum = 0.0
    private var sampleCount = 0
    private var envelope = KnockEnvelopeDetector()
    public init() {}

    public mutating func process(time: Double, acceleration: SIMD3<Double>) -> Bool {
        guard time.isFinite, acceleration.x.isFinite, acceleration.y.isFinite, acceleration.z.isFinite else {
            self = Self(); return false
        }
        guard let previous = lastTime, let oldGravity = gravity,
              time > previous, time - previous < 0.05 else {
            self = Self(); gravity = acceleration; lastTime = time; origin = time
            return false
        }
        lastTime = time
        let alpha = 1 - exp(-(time - previous) / 0.12)
        let updated = oldGravity + (acceleration - oldGravity) * alpha
        gravity = updated
        let dynamic = acceleration - updated
        let energySquared = dynamic.x * dynamic.x + dynamic.y * dynamic.y + dynamic.z * dynamic.z
        let nextBlock = Int((time - origin) / 0.005)
        var recognized = false
        if nextBlock != block {
            if sampleCount > 0 {
                recognized = envelope.process(time: Double(block) * 0.005,
                    rms: sqrt(squareSum / Double(sampleCount)))
            }
            block = nextBlock; squareSum = 0; sampleCount = 0
        }
        squareSum += energySquared; sampleCount += 1
        return recognized
    }
}

/// Consumes 5 ms strength summaries, not individual oscillations. A 15 ms RMS
/// envelope separates impacts even when the chassis continues ringing between them.
struct KnockEnvelopeDetector: Sendable {
    private var recentSquares: [Double] = []
    private var history: [(time: Double, strength: Double)] = []
    private var first: (time: Double, strength: Double)?
    private var cooldownUntil = 0.0

    mutating func process(time: Double, rms: Double) -> Bool {
        recentSquares.append(rms * rms)
        if recentSquares.count > 3 { recentSquares.removeFirst() }
        guard recentSquares.count == 3 else { return false }
        let strength = sqrt(recentSquares.reduce(0, +) / 3)
        history.append((time, strength))
        history.removeAll { $0.time < time - 1.2 }
        guard history.count >= 11 else { return false }
        // A short look-ahead confirms local peaks; no long quiet gap is required.
        let index = history.count - 6
        let candidate = history[index]
        guard candidate.time >= 0.5, candidate.time >= cooldownUntil,
              candidate.strength >= 0.022 else { return false }
        let neighbors = history[(index - 5)...(index + 5)]
        guard !neighbors.contains(where: { $0.strength > candidate.strength }),
              !history[(index - 5)..<index].contains(where: { $0.strength == candidate.strength }) else { return false }
        if let first, candidate.time - first.time > 0.65 { self.first = nil }
        if let first {
            let gap = candidate.time - first.time
            // Ignore early ringing peaks without throwing away the first impact.
            guard gap >= 0.12 else { return false }
            let trough = history.filter { $0.time > first.time && $0.time < candidate.time }
                .map(\.strength).min() ?? .infinity
            // The second impact must rise distinctly above the intervening ringing
            // and be substantial relative to the first, rather than a weak echo.
            guard candidate.strength >= first.strength * 0.45,
                  candidate.strength >= trough * 1.6 else { return false }
            self.first = nil; cooldownUntil = candidate.time + 0.7
            return true
        }
        // Exclude the impact's rising edge from the lead-in estimate. Require high
        // contrast above recent vibration as well as a reasonably quiet baseline.
        let lead = history.filter { $0.time >= candidate.time - 0.3 && $0.time < candidate.time - 0.06 }
        guard !lead.isEmpty else { return false }
        let baseline = sqrt(lead.reduce(0) { $0 + $1.strength * $1.strength } / Double(lead.count))
        if baseline < 0.008, candidate.strength >= max(0.0015, baseline) * 8 { first = candidate }
        return false
    }
}
