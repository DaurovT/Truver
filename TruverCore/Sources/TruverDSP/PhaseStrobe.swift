#if canImport(Darwin)
import Darwin
#elseif canImport(Android)
import Android
#elseif canImport(Glibc)
import Glibc
#endif
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// What the strobe ring shows (TU-10).
public struct StrobeReading: Equatable, Sendable {
    /// Deviation from the target in cents, from the phase drift (0.1-cent class on a sustained note).
    public var cents: Double
    /// Ring angle in degrees (0..<360): the signal phase against the reference — it turns at 360° × Δf per second.
    public var angle: Double
    /// Enough sustained signal for a trustworthy value.
    public var isStable: Bool
    /// Harmonic the reading comes from (1 = fundamental; low strings often give a stronger 2nd).
    public var harmonic: Int
}

/// TU-10 phase strobe — a separate algorithm from the YIN tuner: the input is mixed with reference oscillators at
/// k × target (k = 1…4), low-passed to baseband, and the unwrapped phase of the strongest harmonic is followed.
/// Its slope over the last `windowSeconds` gives the frequency difference (Δf = slope / 2πk), the phase itself
/// turns the ring. Not thread-safe: feed it from the analysis queue.
public final class PhaseStrobe {
    public let sampleRate: Double
    public var windowSeconds = 0.8
    public var minimumSeconds = 0.35
    /// Residual phase jitter (radians) above which the value is not called stable.
    public var maxJitter = 0.35

    public private(set) var target: Double?

    private static let harmonics = 4
    private let decimation: Int
    private let alpha: Double
    // Oscillators as unit phasors rotated every sample (no trig per sample), renormalised per block.
    private var phasorRe = [Double](repeating: 1, count: harmonics)
    private var phasorIm = [Double](repeating: 0, count: harmonics)
    private var stepRe = [Double](repeating: 1, count: harmonics)
    private var stepIm = [Double](repeating: 0, count: harmonics)
    // Two cascaded one-pole low-pass filters on I and Q.
    private var i1 = [Double](repeating: 0, count: harmonics), q1 = [Double](repeating: 0, count: harmonics)
    private var i2 = [Double](repeating: 0, count: harmonics), q2 = [Double](repeating: 0, count: harmonics)
    private var counter = 0
    private var samplesSinceTarget = 0
    // Decimated history per harmonic: unwrapped phase and magnitude.
    private var phases: [[Double]] = Array(repeating: [], count: harmonics)
    private var magnitudes: [[Double]] = Array(repeating: [], count: harmonics)
    private var lastRaw = [Double](repeating: 0, count: harmonics)
    private var unwrapped = [Double](repeating: 0, count: harmonics)

    public init(sampleRate: Double, cutoff: Double = 20, outputRate: Double = 200) {
        self.sampleRate = sampleRate
        decimation = max(1, Int(sampleRate / outputRate))
        alpha = 1 - exp(-2 * Double.pi * cutoff / sampleRate)
    }

    private var maxHistory: Int { Int(windowSeconds * sampleRate / Double(decimation)) }

    /// Sets the reference frequency; a change of more than 0.5 cent starts the measurement again.
    public func setTarget(_ frequency: Double?) {
        if let frequency, let target, abs(1200 * log2(frequency / target)) < 0.5 { return }
        target = frequency
        reset()
        guard let frequency else { return }
        for k in 0..<Self.harmonics {
            let w = 2 * Double.pi * frequency * Double(k + 1) / sampleRate
            stepRe[k] = cos(w)
            stepIm[k] = -sin(w)
        }
    }

    public func reset() {
        for k in 0..<Self.harmonics {
            phasorRe[k] = 1; phasorIm[k] = 0
            i1[k] = 0; q1[k] = 0; i2[k] = 0; q2[k] = 0
            phases[k].removeAll(keepingCapacity: true)
            magnitudes[k].removeAll(keepingCapacity: true)
            lastRaw[k] = 0; unwrapped[k] = 0
        }
        counter = 0
        samplesSinceTarget = 0
    }

    public func process<S: Collection>(_ samples: S) where S.Element == Float {
        guard target != nil else { return }
        for sample in samples {
            let x = Double(sample)
            for k in 0..<Self.harmonics {
                // Mix down: x · e^(−jωkn).
                let re = phasorRe[k], im = phasorIm[k]
                i1[k] += alpha * (x * re - i1[k]); q1[k] += alpha * (x * im - q1[k])
                i2[k] += alpha * (i1[k] - i2[k]); q2[k] += alpha * (q1[k] - q2[k])
                phasorRe[k] = re * stepRe[k] - im * stepIm[k]
                phasorIm[k] = re * stepIm[k] + im * stepRe[k]
            }
            counter += 1
            samplesSinceTarget += 1
            if counter >= decimation {
                counter = 0
                record()
            }
        }
    }

    private func record() {
        // Settle the filters (~3 time constants) before trusting the phase.
        guard Double(samplesSinceTarget) / sampleRate > 0.03 else { return }
        for k in 0..<Self.harmonics {
            let norm = (phasorRe[k] * phasorRe[k] + phasorIm[k] * phasorIm[k]).squareRoot()
            phasorRe[k] /= norm; phasorIm[k] /= norm
            let raw = atan2(q2[k], i2[k])
            if phases[k].isEmpty {
                unwrapped[k] = raw
            } else {
                var d = raw - lastRaw[k]
                while d > .pi { d -= 2 * .pi }
                while d < -.pi { d += 2 * .pi }
                unwrapped[k] += d
            }
            lastRaw[k] = raw
            phases[k].append(unwrapped[k])
            magnitudes[k].append((i2[k] * i2[k] + q2[k] * q2[k]).squareRoot())
            if phases[k].count > maxHistory {
                phases[k].removeFirst(phases[k].count - maxHistory)
                magnitudes[k].removeFirst(magnitudes[k].count - maxHistory)
            }
        }
    }

    /// The current reading, or nil without a target or before the first data.
    public func reading() -> StrobeReading? {
        guard let target, let count = phases.first?.count, count >= 8 else { return nil }
        // The strongest harmonic over the window.
        let means = magnitudes.map { $0.reduce(0, +) / Double(max(1, $0.count)) }
        let k = means.indices.max { means[$0] < means[$1] } ?? 0
        let ys = phases[k]
        let dt = Double(decimation) / sampleRate
        let n = Double(ys.count)
        let meanX = (n - 1) / 2 * dt
        let meanY = ys.reduce(0, +) / n
        var sxy = 0.0, sxx = 0.0
        for (i, y) in ys.enumerated() {
            let x = Double(i) * dt - meanX
            sxy += x * (y - meanY); sxx += x * x
        }
        let slope = sxx > 0 ? sxy / sxx : 0
        var residual = 0.0
        for (i, y) in ys.enumerated() {
            let fit = meanY + slope * (Double(i) * dt - meanX)
            residual += (y - fit) * (y - fit)
        }
        let jitter = (residual / n).squareRoot()
        let harmonic = Double(k + 1)
        let deltaF = slope / (2 * .pi * harmonic)
        let cents = 1200 * log2(max(1e-9, (target + deltaF) / target))
        // The ring follows the signal phase (of the fundamental): it turns at 360° × Δf per second.
        var angle = (ys[ys.count - 1] / harmonic) * 180 / .pi   // sharp turns clockwise, as StrobeRotation
        angle = angle.truncatingRemainder(dividingBy: 360)
        if angle < 0 { angle += 360 }
        let seconds = n * dt
        return StrobeReading(cents: cents, angle: angle, isStable: seconds >= minimumSeconds && jitter < maxJitter, harmonic: k + 1)
    }
}
