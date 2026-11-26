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
import TruverDSP
import TruverTheory

/// Bridge commands of the Tuner feature (Flutter: lib/features/tuner). Method names: "tuner.<name>".
/// Live readings come from `audio.poll` (AudioCommands.swift); these are the static facts the tuner screen and the
/// intonation check need about the current tuning, computed by the core as `TunerScreen.swift` /
/// `IntonationSheet.swift` do with `app.tuning`, `app.formatter` and `Intonation`.
extension Bridge {
    func registerTuner() {
        struct OpenString: Encodable {
            /// `AppModel.stringName(ref)`: «F♯1», «H1».
            var label: String
            /// Open pitch with its sweetened offset, Hz at the tuning's A4.
            var frequency: Double
            var cents: Double
        }
        struct CourseInfo: Encodable {
            /// `formatter.string(spelled.name)`: «F♯», «соль♯».
            var name: String
            /// `formatter.short(spelled.name)` for the string keys: «F♯», «сол♯».
            var short: String
            var octave: Int
            var strings: [OpenString]
            /// IntonationSheet `scaleLength(for:)`: the course's own scale (fanned frets), else the instrument's.
            var scaleLength: Double
        }
        struct StringsDTO: Encodable {
            var courses: [CourseInfo]
            var a4: Double
        }
        /// Strings of the current tuning in physical order (0 = lowest): note names, octaves, open frequencies.
        register("tuner.strings") { [unowned self] _ in
            let t = tuning
            let spelled = t.spelledNotes
            let i = instrument
            let courses = t.openCents.indices.map { c -> CourseInfo in
                let main = spelled[c]
                let strings = t.openCents[c].indices.map { s -> OpenString in
                    let pitch = t.openPitch(course: c, string: s)
                    return OpenString(label: formatter.string(SpelledNote(main.name, midi: pitch.nearestMIDI)),
                                      frequency: pitch.frequency(a4: a4), cents: pitch.cents)
                }
                return CourseInfo(name: formatter.string(main.name), short: formatter.short(main.name), octave: main.octave,
                                  strings: strings, scaleLength: Self.scaleLength(i, course: c))
            }
            return StringsDTO(courses: courses, a4: a4)
        }

        /// `Intonation.steadyFrequency`: the median of the last 16 readings once they agree within ±4 c, else null.
        struct SteadyParams: Decodable { var readings: [Double] }
        struct Steady: Encodable { var frequency: Double? }
        register("tuner.steadyFrequency", SteadyParams.self) { p in
            Steady(frequency: Intonation.steadyFrequency(p.readings))
        }

        /// TU-11 result: `cents` (or `open` + `twelfth` → `Intonation.error`), its verdict and the saddle move.
        struct IntonationParams: Decodable {
            var cents: Double?
            var open: Double?
            var twelfth: Double?
            var course: Int
        }
        struct IntonationResult: Encodable {
            var cents: Double
            /// "ok", "awayFromNeck", "towardsNeck".
            var verdict: String
            /// Saddle move in mm (signed: + away from the neck).
            var saddleShift: Double
        }
        register("tuner.intonation", IntonationParams.self) { [unowned self] p in
            let cents = p.cents ?? Intonation.error(open: p.open ?? 1, twelfth: p.twelfth ?? 2)
            let verdict: String
            switch Intonation.verdict(cents: cents) {
            case .ok: verdict = "ok"
            case .awayFromNeck: verdict = "awayFromNeck"
            case .towardsNeck: verdict = "towardsNeck"
            }
            return IntonationResult(cents: cents, verdict: verdict,
                                    saddleShift: Intonation.saddleShift(cents: cents, scaleLength: Self.scaleLength(instrument, course: p.course)))
        }
    }

    /// IntonationSheet `scaleLength(for:)` with `InstrumentSheet.defaultScale` (TuningsSheet.swift) as the fallback.
    static func scaleLength(_ i: Instrument, course c: Int) -> Double {
        if let m = i.multiscale { return m.scaleLength(course: c, courses: i.courses.count) }
        if c >= 0, c < i.courses.count, let length = i.courses[c].strings.first?.scaleLength { return length }
        switch i.type {
        case .bass: return 864
        case .ukulele: return 330
        case .mandolin: return 350
        default: return i.courses.count >= 8 ? 686 : 648
        }
    }
}
