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

/// TU-11 «Проверка мензуры»: the 12th-fret note against the octave of the open string.
public enum Intonation {
    /// Within this the string is fine.
    public static let okCents = 2.0

    /// 12th fret − 2 × open, in cents (positive: the fretted octave is sharp — the string is too short).
    public static func error(open: Double, twelfth: Double) -> Double {
        1200 * log2(twelfth / (2 * open))
    }

    /// Saddle move in millimetres that cancels `cents` on a string of `scaleLength` mm (after retuning):
    /// positive — away from the neck (sharp octave), negative — towards the neck. ≈ 2.7 c per mm on 648 mm.
    public static func saddleShift(cents: Double, scaleLength: Double) -> Double {
        // d(cents)/d(length) = −1200 / (ln 2 · L) for the octave ratio (L + d) / (L/2 + d).
        cents * scaleLength * log(2) / 1200
    }

    public enum Verdict: Equatable, Sendable { case ok, awayFromNeck, towardsNeck }

    public static func verdict(cents: Double) -> Verdict {
        if abs(cents) <= okCents { return .ok }
        return cents > 0 ? .awayFromNeck : .towardsNeck
    }

    /// Median of steady readings: nil until there are `minimumCount` values within `spreadCents` of the median.
    public static func steadyFrequency(_ readings: [Double], minimumCount: Int = 16, spreadCents: Double = 4) -> Double? {
        guard readings.count >= minimumCount else { return nil }
        let recent = Array(readings.suffix(minimumCount)).sorted()
        let median = recent[recent.count / 2]
        let steady = recent.allSatisfy { abs(1200 * log2($0 / median)) <= spreadCents }
        return steady ? median : nil
    }
}
