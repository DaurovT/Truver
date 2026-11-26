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
import TruverTheory

struct TemplateDTO: Encodable {
    var id: String
    var type: String
    var name: String
    var courses: Int
    /// «E2 A2 D3 G3 B3 E4» in the app's notation.
    var notes: [String]
}

struct StringDTO: Encodable {
    var course: Int
    var string: Int
    /// «E», «соль» (short form for keys, 5.1.4).
    var name: String
    var octave: Int
    var cents: Double
    var frequency: Double
}

extension Bridge {
    func registerTheory() {
        register("theory.templates") { [unowned self] _ in
            TuningTemplates.byPopularity(TuningTemplates.all).map { t in
                TemplateDTO(id: t.id, type: t.type.rawValue, name: t.names.ru, courses: t.courseCount,
                            notes: t.notes.map { formatter.string($0) })
            }
        }

        struct TemplateParams: Decodable { var id: String; var fretCount: Int? }
        register("theory.instrumentFromTemplate", TemplateParams.self) { p in
            guard let template = TuningTemplates.template(id: p.id) else { throw BridgeError("no template \(p.id)") }
            var instrument = template.makeInstrument()
            if let frets = p.fretCount { instrument.fretCount = frets }
            return instrument
        }

        /// Strings of the current tuning, low to high, with names for the tuner keys.
        register("theory.strings") { [unowned self] _ in
            var result: [StringDTO] = []
            for course in 0..<tuning.openCents.count {
                for string in 0..<tuning.openCents[course].count {
                    let pitch = tuning.openPitch(course: course, string: string)
                    let main = tuning.spelledNotes[course]
                    let note = SpelledNote(main.name, midi: pitch.nearestMIDI)
                    result.append(StringDTO(course: course, string: string, name: formatter.short(note.name), octave: note.octave,
                                            cents: pitch.cents, frequency: pitch.frequency(a4: a4)))
                }
            }
            return result
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
