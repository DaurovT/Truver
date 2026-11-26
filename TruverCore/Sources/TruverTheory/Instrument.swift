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

/// Instrument types (PRD 5.1.1). The type decides whether the tuning generator can be used.
public enum InstrumentType: String, CaseIterable, Sendable, Codable {
    case guitar
    /// Guitar with an extra high string (9-string "with high A").
    case guitarExtendedHigh
    case bass
    case ukulele
    case mandolin
    case dutar
    case tanbur
    case rubob

    /// Interval template of the generator, nil for types that only have templates and manual tuning.
    public var intervalTemplate: IntervalTemplate? {
        switch self {
        case .guitar: return .guitar
        case .guitarExtendedHigh: return .guitarExtendedHigh
        case .bass: return .bass
        case .ukulele, .mandolin, .dutar, .tanbur, .rubob: return nil
        }
    }
}

/// How the strings of one course relate (PRD 5.1.2).
public enum CoursePairing: String, Sendable, Codable {
    case single
    case unison
    case octave

    public var stringCount: Int { self == .single ? 1 : 2 }
}

/// Physical properties of one string.
public struct StringSpec: Hashable, Sendable, Codable {
    /// Gauge in inches (0.010 …), optional in v1 (needed by the tension calculator WS-1, P2).
    public var gauge: Double?
    /// Scale length in millimetres; nil = instrument default.
    public var scaleLength: Double?

    public init(gauge: Double? = nil, scaleLength: Double? = nil) {
        self.gauge = gauge
        self.scaleLength = scaleLength
    }
}

/// One position across the neck: one string or a pair (PRD 5.1.2). Array order = physical order,
/// from the bass side, independent of pitch (re-entrant tunings, PR-9).
public struct Course: Hashable, Sendable, Codable {
    public var strings: [StringSpec]
    public var pairing: CoursePairing
    /// First playable fret (reserved for short strings such as the banjo 5th string, P2).
    public var startFret: Int

    public init(pairing: CoursePairing = .single, strings: [StringSpec]? = nil, startFret: Int = 0) {
        self.pairing = pairing
        self.strings = strings ?? Array(repeating: StringSpec(), count: pairing.stringCount)
        self.startFret = startFret
    }
}

/// Fret positions (PR-8: the data model supports non-12-TET frets in v1).
public enum FretSystem: Hashable, Sendable, Codable {
    case equalTempered
    /// Cents above the open string for frets 1, 2, 3, …
    case custom([Double])

    /// Cents above the open string at `fret` (0 = open), nil if the fret does not exist.
    public func cents(atFret fret: Int) -> Double? {
        guard fret >= 0 else { return nil }
        if fret == 0 { return 0 }
        switch self {
        case .equalTempered: return Double(fret) * 100
        case .custom(let table): return fret <= table.count ? table[fret - 1] : nil
        }
    }
}

/// Fanned frets (PR-7, P1).
public struct Multiscale: Hashable, Sendable, Codable {
    public var bassScaleLength: Double
    public var trebleScaleLength: Double
    public var neutralFret: Int

    public init(bassScaleLength: Double, trebleScaleLength: Double, neutralFret: Int) {
        self.bassScaleLength = bassScaleLength
        self.trebleScaleLength = trebleScaleLength
        self.neutralFret = neutralFret
    }

    /// Scale length of a course (0 = lowest), linear from bass to treble — as on a fanned neck.
    public func scaleLength(course: Int, courses: Int) -> Double {
        guard courses > 1 else { return (bassScaleLength + trebleScaleLength) / 2 }
        let t = Double(min(max(course, 0), courses - 1)) / Double(courses - 1)
        return bassScaleLength + (trebleScaleLength - bassScaleLength) * t
    }

    /// Each course's scale length divided by the mean one (low course first).
    public func ratios(courses: Int) -> [Double] {
        let mean = (bassScaleLength + trebleScaleLength) / 2
        return (0..<max(1, courses)).map { scaleLength(course: $0, courses: courses) / mean }
    }

    /// Position of a fret wire along the neck in millimetres, measured from the neutral fret towards the bridge
    /// (negative towards the nut). At the neutral fret every course gives 0 — the wire is square to the strings.
    public func fretPosition(course: Int, fret: Int, courses: Int) -> Double {
        let l = scaleLength(course: course, courses: courses)
        func fromNut(_ n: Int) -> Double { l * (1 - pow(2, -Double(n) / 12)) }
        return fromNut(fret) - fromNut(neutralFret)
    }

    /// Common setups: «27″–25.5″» on 8 strings and so on (inch → mm).
    public static func inches(_ bass: Double, _ treble: Double, neutralFret: Int) -> Multiscale {
        Multiscale(bassScaleLength: bass * 25.4, trebleScaleLength: treble * 25.4, neutralFret: neutralFret)
    }
}

public enum Temperament: Hashable, Sendable, Codable {
    case equal
    /// Offsets in cents for the 12 pitch classes from C (TH-10, P2).
    case custom([Double])
}

/// The musical part of an instrument setup (PR-1): open pitches and everything that changes with a tuning.
public struct Tuning: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var name: String
    /// Open pitch of every string, `[course][stringInCourse]`, cents from A4.
    public var openCents: [[Double]]
    /// Sweetened-tuning offsets with the same shape as `openCents` (TU-14, P2). Empty = none.
    public var offsetsCents: [[Double]]
    public var temperament: Temperament
    /// Own A4 in Hz; nil = inherit the app default (PR-5).
    public var a4: Double?
    public var accidentalPreference: AccidentalPreference
    /// True while this tuning is an untouched copy of a template.
    public var isTemplateCopy: Bool
    public var templateId: String?

    public init(id: UUID = UUID(),
                name: String,
                openCents: [[Double]],
                offsetsCents: [[Double]] = [],
                temperament: Temperament = .equal,
                a4: Double? = nil,
                accidentalPreference: AccidentalPreference = .auto,
                isTemplateCopy: Bool = false,
                templateId: String? = nil) {
        self.id = id
        self.name = name
        self.openCents = openCents
        self.offsetsCents = offsetsCents
        self.temperament = temperament
        self.a4 = a4
        self.accidentalPreference = accidentalPreference
        self.isTemplateCopy = isTemplateCopy
        self.templateId = templateId
    }

    public static let a4Range: ClosedRange<Double> = 415...466

    /// A4 in effect: own value or the app default (PR-5).
    public func effectiveA4(default defaultA4: Double) -> Double { a4 ?? defaultA4 }

    /// Open pitch of a string, including its sweetened offset.
    public func openPitch(course: Int, string: Int = 0) -> Pitch {
        var cents = openCents[course][string]
        if course < offsetsCents.count, string < offsetsCents[course].count {
            cents += offsetsCents[course][string]
        }
        return Pitch(cents: cents)
    }

    /// "All strings a semitone down/up" (PR-3).
    public func shifted(bySemitones n: Int) -> Tuning {
        var copy = self
        copy.openCents = openCents.map { $0.map { $0 + Double(n) * 100 } }
        copy.isTemplateCopy = false
        return copy
    }

    /// The main pitch of each course (its first string), in physical order.
    public var coursePitches: [Pitch] { openCents.indices.map { openPitch(course: $0) } }

    /// Note names of the main string of each course, spelled as in PRD 5.1.3.
    public var spelledNotes: [SpelledNote] {
        TuningSpeller.spell(coursePitches, preference: accidentalPreference)
    }
}

public enum EditError: Error, Equatable, Sendable {
    case cannotDeleteLastTuning
    case tuningNotFound
    case shapeMismatch
}

/// The physical instrument (PR-1). In v1 the UI shows one instrument with a list of tunings.
public struct Instrument: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var name: String
    public var type: InstrumentType
    public var courses: [Course]
    public var frets: FretSystem
    public var fretCount: Int
    public var capo: Int
    public var multiscale: Multiscale?
    public var tunings: [Tuning]
    public var currentTuningId: UUID?

    public init(id: UUID = UUID(),
                name: String,
                type: InstrumentType,
                courses: [Course],
                frets: FretSystem = .equalTempered,
                fretCount: Int = 24,
                capo: Int = 0,
                multiscale: Multiscale? = nil,
                tunings: [Tuning] = [],
                currentTuningId: UUID? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.courses = courses
        self.frets = frets
        self.fretCount = fretCount
        self.capo = capo
        self.multiscale = multiscale
        self.tunings = tunings
        self.currentTuningId = currentTuningId ?? tunings.first?.id
    }

    public var currentTuning: Tuning? {
        tunings.first { $0.id == currentTuningId } ?? tunings.first
    }

    /// Does the tuning have exactly one pitch per string of this instrument?
    public func fits(_ tuning: Tuning) -> Bool {
        tuning.openCents.count == courses.count
            && zip(tuning.openCents, courses).allSatisfy { $0.count == $1.strings.count }
    }

    /// Frets that can be played on a course: from the capo (or the course's start fret) to the last fret.
    public func playableFrets(course: Int) -> ClosedRange<Int> {
        max(capo, courses[course].startFret)...fretCount
    }

    /// Pitch of a string at a fret, nil if the fret is not playable.
    public func pitch(course: Int, string: Int = 0, fret: Int, tuning: Tuning) -> Pitch? {
        guard playableFrets(course: course).contains(fret), let cents = frets.cents(atFret: fret) else { return nil }
        return tuning.openPitch(course: course, string: string).transposed(byCents: cents)
    }

    public mutating func addTuning(_ tuning: Tuning, makeCurrent: Bool = true) throws {
        guard fits(tuning) else { throw EditError.shapeMismatch }
        tunings.append(tuning)
        if makeCurrent { currentTuningId = tuning.id }
    }

    /// Deletes a tuning; the last one cannot be deleted (6.2.3).
    public mutating func deleteTuning(id: UUID) throws {
        guard tunings.count > 1 else { throw EditError.cannotDeleteLastTuning }
        guard let index = tunings.firstIndex(where: { $0.id == id }) else { throw EditError.tuningNotFound }
        tunings.remove(at: index)
        if currentTuningId == id { currentTuningId = tunings.first?.id }
    }
}

/// Spelling of tuning notes (PRD 5.1.3): tunings a half step below a natural standard use flats,
/// tunings with F♯ or C♯ at the bottom use sharps. Detected by the top (treble) string:
/// a black key on top means a "half step down" family.
public enum TuningSpeller {
    public static func spell(_ pitches: [Pitch], preference: AccidentalPreference = .auto) -> [SpelledNote] {
        let flats: Bool
        switch preference {
        case .sharp: flats = false
        case .flat: flats = true
        case .auto:
            let top = pitches.last.map { NoteName.simpleSpelling(ofPitchClass: $0.pitchClass, preferFlats: false) }
            flats = (top?.accidental ?? 0) != 0
        }
        return pitches.map { pitch in
            SpelledNote(NoteName.simpleSpelling(ofPitchClass: pitch.pitchClass, preferFlats: flats), midi: pitch.nearestMIDI)
        }
    }
}
