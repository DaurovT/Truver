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

/// TH-8: the user's own scales and chords. The app registers them at launch and after each edit; the libraries
/// (`ScaleLibrary.scale(id:)`, `ChordLibrary.anyChord(id:)`, `ChordLibrary.full`) look here after the built-ins,
/// so progressions, recognition and voicings work with them like with any other.
public final class UserLibrary: @unchecked Sendable {
    public static let shared = UserLibrary()
    private let lock = TheoryLock()
    private var storedScales: [Scale] = []
    private var storedChords: [Chord] = []

    public var scales: [Scale] { lock.withLock { storedScales } }
    public var chords: [Chord] { lock.withLock { storedChords } }

    public func set(scales: [Scale], chords: [Chord]) {
        lock.withLock {
            storedScales = scales
            storedChords = chords
        }
    }
}

extension DegreeLabel {
    /// The usual name of a semitone above the root outside a seven-note context: ♭2, 2, ♭3, 3, 4, ♭5, 5, ♭6, 6, ♭7, 7.
    public static func common(semitones: Int) -> DegreeLabel {
        let table: [(Int, Int)] = [(1, 0), (2, -1), (2, 0), (3, -1), (3, 0), (4, 0), (5, -1), (5, 0), (6, -1), (6, 0), (7, -1), (7, 0)]
        let (n, a) = table[mod(semitones, 12)]
        return DegreeLabel(n, a)
    }
}

extension Scale {
    /// TH-8: a user scale from semitones above the root. Seven notes keep one letter per degree when that needs at
    /// most one accidental (1 ♭2 3 4 5 ♭6 ♭7); otherwise each note gets its common name.
    public static func user(id: String, name: String, semitones: [Int]) -> Scale {
        let steps = Array(Set(semitones.map { mod($0, 12) }).union([0])).sorted()
        var labels = steps.map { DegreeLabel.common(semitones: $0) }
        if steps.count == 7 {
            let heptatonic = steps.enumerated().map { i, s in DegreeLabel(i + 1, s - DegreeLabel.majorSemitones(i + 1)) }
            if heptatonic.allSatisfy({ abs($0.accidental) <= 1 }) { labels = heptatonic }
        }
        return Scale(id: id, names: LocalizedText(ru: name, en: name), category: .user,
                     degrees: labels.map(ScaleDegree.init(label:)), isUserDefined: true)
    }

    /// Semitones above the root, ascending.
    public var semitoneSet: [Int] { degrees.map { mod($0.semitones, 12) }.sorted() }
}

extension Chord {
    /// TH-8: a user chord from degree labels («1 3 5 ♭7 ♯11»). The fifth may be dropped in chords of four or more
    /// notes, as in the built-in library.
    public static func user(id: String, name: String, symbol: String, labels: [DegreeLabel]) -> Chord {
        var unique: [DegreeLabel] = []
        for l in [DegreeLabel(1)] + labels where !unique.contains(l) { unique.append(l) }
        unique.sort { $0.number == $1.number ? $0.accidental < $1.accidental : $0.number < $1.number }
        let text = unique.map(\.description).joined(separator: " ")
        let optional = unique.count >= 4 && unique.contains(DegreeLabel(5)) ? "5" : ""
        return Chord(id: id, symbol: symbol, names: LocalizedText(ru: name, en: name), category: .user,
                     labels: text, optional: optional, isUserDefined: true)
    }
}
