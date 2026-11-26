#if canImport(Accelerate) && !TRUVER_PORTABLE_DSP
import Accelerate
#endif
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

/// Difference function of one analysis frame (YIN, de Cheveigné & Kawahara 2002), kept so that other
/// lags can be inspected afterwards (octave check TU-4).
///
/// `d(τ) = Σ_{j<W} (x[j] − x[j+τ])²`, computed as `e(0) + e(τ) − 2·r(τ)` with the correlation `r` done by
/// vDSP. The normalised form `dn(τ) = d(τ) / (e(0) + e(τ))` lies in 0…2 and is 0 for a perfect period.
public struct YINFrame {
    public let sampleRate: Double
    public let window: Int
    public let maxLag: Int
    /// Raw difference, index = lag (0…maxLag).
    public let difference: [Double]
    /// Cumulative mean normalised difference d′(τ), index = lag.
    public let cmnd: [Double]
    /// Energy-normalised difference dn(τ), index = lag.
    public let normalized: [Double]
    /// Mean square of the frame (signal level).
    public let meanSquare: Double

    /// `samples` must hold at least `window + maxLag` values; the frame uses the first ones.
    public init(samples: UnsafeBufferPointer<Float>, sampleRate: Double, window: Int, maxLag: Int) {
        precondition(window > 0 && maxLag > 1 && samples.count >= window + maxLag, "Frame too short")
        self.sampleRate = sampleRate
        self.window = window
        self.maxLag = maxLag

        let base = samples.baseAddress!
        var correlation = [Float](repeating: 0, count: maxLag + 1)
        correlation.withUnsafeMutableBufferPointer { out in
            #if canImport(Accelerate) && !TRUVER_PORTABLE_DSP
            vDSP_conv(base, 1, base, 1, out.baseAddress!, 1, vDSP_Length(maxLag + 1), vDSP_Length(window))
            #else
            PortableDSP.autocorrelation(base, window: window, maxLag: maxLag, into: out.baseAddress!)
            #endif
        }

        // Prefix sums of squares in Double for e(τ) = Σ_{j=τ}^{τ+W−1} x[j]².
        var prefix = [Double](repeating: 0, count: window + maxLag + 1)
        for i in 0..<(window + maxLag) {
            let v = Double(samples[i])
            prefix[i + 1] = prefix[i] + v * v
        }
        let e0 = prefix[window]
        var d = [Double](repeating: 0, count: maxLag + 1)
        var n = [Double](repeating: 0, count: maxLag + 1)
        for tau in 1...maxLag {
            let eTau = prefix[tau + window] - prefix[tau]
            let value = max(0, e0 + eTau - 2 * Double(correlation[tau]))
            d[tau] = value
            n[tau] = e0 + eTau > 0 ? value / (e0 + eTau) : 1
        }
        var c = [Double](repeating: 1, count: maxLag + 1)
        var running = 0.0
        for tau in 1...maxLag {
            running += d[tau]
            c[tau] = running > 0 ? d[tau] * Double(tau) / running : 1
        }
        self.difference = d
        self.cmnd = c
        self.normalized = n
        self.meanSquare = e0 / Double(window)
    }

    /// Lag of the local minimum of `normalized` near `lag` (±`radius`), refined by parabolic interpolation.
    public func refinedMinimum(near lag: Int, radius: Int = 2) -> (lag: Double, value: Double)? {
        let lo = max(2, lag - radius), hi = min(maxLag - 1, lag + radius)
        guard lo <= hi else { return nil }
        var best = lo
        for t in lo...hi where normalized[t] < normalized[best] { best = t }
        return parabolic(normalized, at: best)
    }

    func parabolic(_ values: [Double], at t: Int) -> (lag: Double, value: Double) {
        guard t > 1, t < values.count - 1 else { return (Double(t), values[t]) }
        let a = values[t - 1], b = values[t], c = values[t + 1]
        let denominator = a - 2 * b + c
        guard denominator > 1e-12 else { return (Double(t), b) }
        let shift = 0.5 * (a - c) / denominator
        guard abs(shift) < 1 else { return (Double(t), b) }
        return (Double(t) + shift, b - 0.25 * (a - c) * shift)
    }

    /// Standard YIN pick: the first lag in `minLag…maxLag` whose d′ falls below `threshold`, followed down
    /// to its local minimum; if none, the global minimum. The period is refined on the raw difference.
    public func estimate(minLag: Int, threshold: Double) -> YINEstimate? {
        let lo = max(2, minLag), hi = maxLag - 1
        guard lo < hi else { return nil }
        var tau: Int?
        var t = lo
        while t <= hi {
            if cmnd[t] < threshold {
                while t + 1 <= hi && cmnd[t + 1] < cmnd[t] { t += 1 }
                tau = t
                break
            }
            t += 1
        }
        if tau == nil {
            var best = lo
            for i in lo...hi where cmnd[i] < cmnd[best] { best = i }
            tau = best
        }
        guard let found = tau else { return nil }
        let refined = parabolic(difference, at: found)
        return YINEstimate(period: refined.lag, frequency: sampleRate / refined.lag,
                           aperiodicity: cmnd[found], normalizedDifference: normalized[found])
    }
}

public struct YINEstimate: Hashable, Sendable {
    /// Period in samples (fractional).
    public var period: Double
    public var frequency: Double
    /// d′ at the chosen lag: 0 = perfectly periodic; above ~0.3 the frame is treated as unvoiced.
    public var aperiodicity: Double
    /// dn at the chosen lag.
    public var normalizedDifference: Double
}

/// Octave and twelfth check (TU-4): is the true note k = 2 or 3 times lower than the found one?
///
/// A signal with period T is also periodic with 2T and 3T, so the longer lag always looks good in absolute
/// terms. The test is relative: the longer lag must be clearly better, `dn(kT) < ratio · dn(T)`, and the found
/// lag must itself be imperfect, `dn(T) > floor` (for a true high note both are near zero).
public struct OctaveCheck: Sendable {
    public var ratio: Double
    public var floor: Double

    public init(ratio: Double = 0.5, floor: Double = 0.003) {
        self.ratio = ratio
        self.floor = floor
    }

    /// Returns the corrected estimate, or the original one when no correction applies.
    /// `minFrequency` bounds the candidates (no note below the instrument's range).
    public func apply(_ estimate: YINEstimate, frame: YINFrame, minFrequency: Double) -> (estimate: YINEstimate, factor: Int) {
        guard let found = frame.refinedMinimum(near: Int(estimate.period.rounded()), radius: 1),
              found.value > floor else { return (estimate, 1) }
        var best: (YINEstimate, Int, Double)?
        for k in [2, 3] {
            let lag = estimate.period * Double(k)
            guard Int(lag.rounded()) + 2 <= frame.maxLag, frame.sampleRate / lag >= minFrequency,
                  let candidate = frame.refinedMinimum(near: Int(lag.rounded()), radius: k) else { continue }
            if candidate.value < ratio * found.value, best == nil || candidate.value < best!.2 {
                // Refine the period on the raw difference around the candidate.
                let t = Int(candidate.lag.rounded())
                let refined = frame.parabolic(frame.difference, at: min(max(t, 2), frame.maxLag - 1))
                let corrected = YINEstimate(period: refined.lag, frequency: frame.sampleRate / refined.lag,
                                            aperiodicity: frame.cmnd[t], normalizedDifference: candidate.value)
                best = (corrected, k, candidate.value)
            }
        }
        guard let best else { return (estimate, 1) }
        return (best.0, best.1)
    }
}
