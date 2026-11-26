#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import TruverDSP
import TruverTheory

/// Bridge commands of the app shell (Flutter: lib/app/app_model.dart, lib/features/root, lib/features/onboarding).
/// Method names: "shell.<name>". Everything that `AppModel.swift` computes with the core lives here, so the Dart
/// side never re-models the theory.
extension Bridge {
    func registerShell() {
        /// Default values of the core types inside `AppSettings` (Storage.swift), encoded by the core itself so
        /// the Dart settings stay Codable-compatible: `MeterSettings(bpm: 100)`, `NoteName(.g)`, the default song map…
        struct Defaults: Encodable {
            var meter: MeterSettings
            var tonic: NoteName
            var layout: LayoutKind
            var eightNotePattern: EightNotePattern
            var clickPattern: ClickPattern
            var song: [SongSection]
            var clickSound: ClickSounds.Kind
        }
        register("shell.defaults") { _ in
            Defaults(meter: MeterSettings(bpm: 100), tonic: NoteName(.g), layout: .threeNotesPerString,
                     eightNotePattern: .threeThreeTwo, clickPattern: .backbeats,
                     song: [SongSection(name: "Вступление", bpm: 120, bars: 4), SongSection(name: "Куплет", bpm: 120, bars: 8),
                            SongSection(name: "Припев", bpm: 128, bars: 8)],
                     clickSound: .click)
        }

        /// `AppModel.stringName`: «B1», «F♯1», «H1» — a string of the current tuning with its octave.
        struct StringParams: Decodable { var course: Int; var string: Int? }
        register("shell.stringName", StringParams.self) { [unowned self] p in
            let t = tuning
            guard p.course >= 0, p.course < t.openCents.count else { throw BridgeError("no course \(p.course)") }
            let pitch = t.openPitch(course: p.course, string: p.string ?? 0)
            let main = t.spelledNotes[p.course]
            return formatter.string(SpelledNote(main.name, midi: pitch.nearestMIDI))
        }

        /// `AppModel.chromaticName`: the nearest note of `cents` (from A4 = 440) with the tuning's accidental family.
        struct CentsParams: Decodable { var cents: Double }
        register("shell.chromaticName", CentsParams.self) { [unowned self] p in
            let pitch = Pitch(cents: p.cents)
            let flats = tuning.spelledNotes.contains { $0.name.accidental < 0 }
            return formatter.string(SpelledNote(NoteName.simpleSpelling(ofPitchClass: pitch.pitchClass, preferFlats: flats),
                                                midi: pitch.nearestMIDI))
        }

        /// `AppModel.noteName`: a spelled note (`{"name": NoteName, "octave": n}`) or a bare name in the app's notation.
        struct NoteParams: Decodable { var name: NoteName; var octave: Int? }
        register("shell.noteName", NoteParams.self) { [unowned self] p in
            if let octave = p.octave { return formatter.string(SpelledNote(p.name, octave: octave)) }
            return formatter.string(p.name)
        }

        /// TH-8: the user's own scales and chords from the settings (`UserLibrary.shared.set`), sent by `AppModel`
        /// at start and whenever `customScales` / `customChords` change.
        struct LibraryParams: Decodable { var scales: [Scale]; var chords: [Chord] }
        register("shell.userLibrary", LibraryParams.self) { p in
            UserLibrary.shared.set(scales: p.scales, chords: p.chords)
            return Done()
        }

        /// `AppModel.addTemplate`: a template of the same type and string count is added to the current instrument
        /// (and becomes current); `{"instrument": …}`. Otherwise `{"incompatible": true}` — call `shell.replaceInstrument`.
        struct TemplateParams: Decodable { var id: String; var fretCount: Int? }
        struct AddResult: Encodable { var instrument: Instrument?; var incompatible: Bool }
        register("shell.addTemplate", TemplateParams.self) { [unowned self] p in
            guard let template = TuningTemplates.template(id: p.id) else { throw BridgeError("no template \(p.id)") }
            guard TuningTemplates.isCompatible(template, with: instrument) else { return AddResult(instrument: nil, incompatible: true) }
            var copy = instrument
            try copy.addTuning(template.makeTuning())
            return AddResult(instrument: copy, incompatible: false)
        }

        /// `AppModel.replaceInstrument(with:fretCount:)` (6.1 п. 19): a new instrument from a template; `fretCount` is
        /// the user's choice, nil keeps the current fret count within the same family (guitars, basses).
        register("shell.replaceInstrument", TemplateParams.self) { [unowned self] p in
            guard let template = TuningTemplates.template(id: p.id) else { throw BridgeError("no template \(p.id)") }
            var replacement = template.makeInstrument()
            func family(_ t: InstrumentType) -> Int {
                switch t {
                case .guitar, .guitarExtendedHigh: return 0
                case .bass: return 1
                default: return 2
                }
            }
            if let frets = p.fretCount {
                replacement.fretCount = frets
            } else if family(replacement.type) == family(instrument.type) && family(replacement.type) < 2 {
                replacement.fretCount = instrument.fretCount
            }
            return replacement
        }
    }
}
