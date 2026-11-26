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

/// Edits of the instrument that touch every tuning (6.1 п. 19, 20).
public enum InstrumentEditing {
    public enum Side: Sendable { case low, high }

    /// What changed, for the confirmation dialog and for opening manual tuning afterwards.
    public struct Report: Hashable, Sendable {
        public var affectedTuningIds: [UUID]
        /// Courses (by index in the new instrument) whose pitch was copied from a neighbour and must be
        /// tuned by hand — types without an interval template.
        public var needsManualTuning: [Int]
    }

    /// Changes the number of courses, adding or removing them on `side` (6.1 п. 20).
    /// New strings get a fourth beyond the edge string for types with an interval template, otherwise
    /// the pitch of the neighbouring string. Removed strings are dropped from every tuning.
    public static func changingStringCount(of instrument: Instrument, to newCount: Int, side: Side,
                                           language: Language = .ru) -> (Instrument, Report) {
        precondition(newCount >= 1, "An instrument needs at least one string")
        var result = instrument
        let delta = newCount - instrument.courses.count
        guard delta != 0 else { return (instrument, Report(affectedTuningIds: [], needsManualTuning: [])) }

        let hasTemplate = instrument.type.intervalTemplate != nil
        var manual: [Int] = []

        if delta > 0 {
            let edgeCourse = side == .low ? instrument.courses.first! : instrument.courses.last!
            let added = Array(repeating: Course(pairing: edgeCourse.pairing), count: delta)
            result.courses = side == .low ? added + instrument.courses : instrument.courses + added
            if !hasTemplate {
                manual = side == .low ? Array(0..<delta) : Array(instrument.courses.count..<newCount)
            }
            result.tunings = instrument.tunings.map { tuning in
                var t = tuning
                var edge = side == .low ? tuning.openCents.first![0] : tuning.openCents.last![0]
                var newCourses: [[Double]] = []
                for _ in 0..<delta {
                    if hasTemplate { edge += side == .low ? -500 : 500 }
                    newCourses.append(strings(main: edge, pairing: edgeCourse.pairing))
                }
                if side == .low {
                    t.openCents = newCourses.reversed() + tuning.openCents
                    if !tuning.offsetsCents.isEmpty { t.offsetsCents = newCourses.map { $0.map { _ in 0 } } + tuning.offsetsCents }
                } else {
                    t.openCents = tuning.openCents + newCourses
                    if !tuning.offsetsCents.isEmpty { t.offsetsCents = tuning.offsetsCents + newCourses.map { $0.map { _ in 0 } } }
                }
                t.isTemplateCopy = false
                return t
            }
        } else {
            let removeCount = -delta
            let keep = side == .low ? removeCount..<instrument.courses.count : 0..<newCount
            result.courses = Array(instrument.courses[keep])
            result.tunings = instrument.tunings.map { tuning in
                var t = tuning
                t.openCents = Array(tuning.openCents[keep])
                if !tuning.offsetsCents.isEmpty { t.offsetsCents = Array(tuning.offsetsCents[keep]) }
                t.isTemplateCopy = false
                return t
            }
        }
        renameAfterResize(&result, from: instrument, language: language)
        return (result, Report(affectedTuningIds: instrument.tunings.map(\.id), needsManualTuning: manual))
    }

    /// Names that described the old string count follow the new one (found on the iPhone: after 7 → 8 the switcher
    /// still read «7-струнная · Стандарт B»): the automatic instrument name, and «Стандарт X» tunings that are
    /// still the standard pattern get the new lowest note. Names the user typed stay.
    static func renameAfterResize(_ result: inout Instrument, from old: Instrument, language: Language) {
        if old.name == TuningTemplates.defaultInstrumentName(type: old.type, courses: old.courses.count, language: language) {
            result.name = TuningTemplates.defaultInstrumentName(type: result.type, courses: result.courses.count, language: language)
        }
        guard let pattern = result.type.intervalTemplate else { return }
        let prefix = language == .ru ? "Стандарт " : "Standard "
        for i in result.tunings.indices {
            let t = result.tunings[i]
            guard t.name.hasPrefix(prefix), t.openCents.count == result.courses.count else { continue }
            let mains = t.openCents.map { $0[0] }
            let steps = zip(mains, mains.dropFirst()).map { Int((($1 - $0) / 100).rounded()) }
            guard steps == pattern.intervals(stringCount: mains.count) else { continue }
            let low = t.spelledNotes[0].name
            let newName = prefix + low.description
            guard newName != t.name, !result.tunings.contains(where: { $0.name == newName && $0.id != t.id }) else { continue }
            result.tunings[i].name = newName
        }
    }

    /// Changes the pairing of one course (6.1 п. 20): the second string is a unison or an octave above.
    public static func changingPairing(of instrument: Instrument, course index: Int, to pairing: CoursePairing) -> (Instrument, Report) {
        var result = instrument
        result.courses[index] = Course(pairing: pairing,
                                       strings: Array(instrument.courses[index].strings.prefix(1))
                                           + (pairing == .single ? [] : [StringSpec()]),
                                       startFret: instrument.courses[index].startFret)
        result.tunings = instrument.tunings.map { tuning in
            var t = tuning
            t.openCents[index] = strings(main: tuning.openCents[index][0], pairing: pairing)
            if index < t.offsetsCents.count {
                t.offsetsCents[index] = Array(repeating: 0, count: pairing.stringCount)
            }
            t.isTemplateCopy = false
            return t
        }
        return (result, Report(affectedTuningIds: instrument.tunings.map(\.id), needsManualTuning: []))
    }

    /// Adds a compatible template as a new tuning; incompatible templates must go through
    /// `TuningTemplate.makeInstrument` ("Заменить инструмент", 6.1 п. 19).
    public static func adding(_ template: TuningTemplate, to instrument: Instrument, language: Language = .ru) throws -> Instrument {
        guard TuningTemplates.isCompatible(template, with: instrument) else { throw EditError.shapeMismatch }
        var result = instrument
        try result.addTuning(template.makeTuning(language: language))
        return result
    }

    private static func strings(main: Double, pairing: CoursePairing) -> [Double] {
        switch pairing {
        case .single: return [main]
        case .unison: return [main, main]
        case .octave: return [main, main + 1200]
        }
    }
}
