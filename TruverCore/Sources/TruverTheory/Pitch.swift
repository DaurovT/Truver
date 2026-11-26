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

/// Integer modulo that is always non-negative.
@inline(__always)
func mod(_ value: Int, _ modulus: Int) -> Int {
    ((value % modulus) + modulus) % modulus
}

/// Floating modulo that is always in `0..<modulus`.
@inline(__always)
func mod(_ value: Double, _ modulus: Double) -> Double {
    let r = value.truncatingRemainder(dividingBy: modulus)
    return r < 0 ? r + modulus : r
}

/// A pitch stored as cents relative to A4 (PRD section 4: "Хранение высоты нот — в центах от A4").
///
/// The reference frequency of A4 is not part of the pitch: calibration (PR-5) changes only the
/// number passed to `frequency(a4:)` / `init(frequency:a4:)`.
public struct Pitch: Hashable, Comparable, Sendable, Codable {
    public var cents: Double

    public init(cents: Double) { self.cents = cents }

    /// MIDI-style note number (A4 = 69). Fractional values are allowed for microtonal pitches.
    public init(midi: Double) { self.cents = (midi - 69) * 100 }

    public init(frequency: Double, a4: Double = 440) {
        self.cents = 1200 * log2(frequency / a4)
    }

    public var midi: Double { 69 + cents / 100 }

    public func frequency(a4: Double = 440) -> Double {
        a4 * pow(2, cents / 1200)
    }

    /// Nearest 12-TET note as a MIDI number.
    public var nearestMIDI: Int { Int(midi.rounded()) }

    /// Signed distance in cents from the nearest 12-TET note.
    public var deviationFromNearestSemitone: Double {
        cents - Double(nearestMIDI - 69) * 100
    }

    /// Pitch class of the nearest 12-TET note, C = 0 … B = 11.
    public var pitchClass: Int { mod(nearestMIDI, 12) }

    public func transposed(byCents delta: Double) -> Pitch { Pitch(cents: cents + delta) }
    public func transposed(bySemitones n: Int) -> Pitch { Pitch(cents: cents + Double(n) * 100) }

    /// Cents of the given pitch class inside the octave that starts at A (used for mod-1200 matching).
    static func cents(ofPitchClass pc: Int) -> Double { Double(pc - 9) * 100 }

    public static func < (lhs: Pitch, rhs: Pitch) -> Bool { lhs.cents < rhs.cents }
}
