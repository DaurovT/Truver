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

/// Bridge commands of the Instrument feature (Flutter: lib/features/instrument — port of
/// Truver/Sources/Features/Instrument/TuningsSheet.swift). Method names: "instrument.<name>".
/// They work on the session's instrument (`session.set`, sent by `AppModel` after every edit) and return ready
/// labels in the app's notation, so the Dart sheets never re-model the theory.
extension Bridge {
    func registerInstrument() {
        // MARK: Tunings list and editor

        /// Spelled notes of tunings (their own accidental family, «E♭2 A♭2…»): `{"tunings": [Tuning]}` →
        /// `[[String]]`, one note per course, lowest first.
        struct SpellParams: Decodable { var tunings: [Tuning] }
        register("instrument.spell", SpellParams.self) { [unowned self] p in
            p.tunings.map { $0.spelledNotes.map { formatter.string($0) } }
        }

        // MARK: Template library

        /// `{"category": "drop" | nil, "query"}` → «Библиотека строев»: sections «Drop · 6 струн» of this instrument's
        /// templates (most played first), `exists` — such a tuning is already saved («добавлен»).
        struct LibraryParams: Decodable { var category: String?; var query: String }
        struct TemplateRow: Encodable {
            var id: String
            var name: String
            var notes: String
            var exists: Bool
        }
        struct TemplateGroup: Encodable { var title: String; var templates: [TemplateRow] }
        register("instrument.library", LibraryParams.self) { [unowned self] p in
            let base = TuningTemplates.library(for: instrument, category: p.category.flatMap(TuningCategory.init(rawValue:)))
            let q = String(p.query.lowercased().map { $0 == "#" ? "♯" : $0 })
            func notes(_ t: TuningTemplate) -> String { t.notes.map { formatter.string($0) }.joined(separator: " ") }
            let list = p.query.isEmpty ? base : base.filter { t in
                t.names.ru.lowercased().contains(q) || t.names.en.lowercased().contains(q) || notes(t).lowercased().contains(q)
            }
            let n = instrument.courses.count
            return TuningCategory.allCases.compactMap { kind -> TemplateGroup? in
                let items = list.filter { $0.category == kind }
                guard !items.isEmpty else { return nil }
                return TemplateGroup(title: "\(kind.title) · \(n) \(Inst.plural(n, "струна", "струны", "струн"))",
                                     templates: items.map { t in
                                         TemplateRow(id: t.id, name: t.names.ru, notes: notes(t),
                                                     exists: instrument.tunings.contains { $0.templateId == t.id || $0.hasSamePitches(t.notes.map(\.pitch)) })
                                     })
            }
        }

        // MARK: Generator (canvas «Генератор строя»: Drop / Ниже всё / Open from the current tuning)

        struct RecipeParams: Decodable {
            var mode: String
            var lowest: Int?
            var rest: Int?
            var semitones: Int?
            var root: Int?
            /// Add the result to the instrument (returns the instrument).
            var add: Bool?

            var recipe: TuningRecipe {
                switch mode {
                case "lower": return .lower(semitones: semitones ?? 1)
                case "open": return .open(root: root ?? 7)
                default: return .drop(lowest: lowest ?? 2, rest: rest ?? 0)
                }
            }
        }
        struct SameTuning: Encodable { var id: String; var name: String }
        struct RecipeResult: Encodable {
            var name: String
            var notes: String
            var warning: String?
            var same: SameTuning?
            /// Names of the Open roots G D E A C F B in the app's notation.
            var roots: [String]
        }
        register("instrument.recipe", RecipeParams.self) { [unowned self] p in
            let r = p.recipe.apply(to: tuning, instrument: instrument, formatter: formatter)
            if p.add == true {
                let flats = r.notes.contains { $0.name.accidental < 0 }, sharps = r.notes.contains { $0.name.accidental > 0 }
                let t = Tuning(name: uniqueName(r.name).0,
                               openCents: zip(r.pitches, instrument.courses).map { pitch, course in
                                   course.pairing == .octave ? [pitch.cents, pitch.cents + 1200]
                                       : Array(repeating: pitch.cents, count: course.strings.count)
                               },
                               accidentalPreference: flats ? .flat : (sharps ? .sharp : .auto), templateId: r.templateId)
                var inst = instrument
                try inst.addTuning(t)
                return inst
            }
            let same = instrument.tunings.first { $0.hasSamePitches(r.pitches) }
            return RecipeResult(name: r.name, notes: r.notes.map { formatter.string($0) }.joined(separator: " "),
                                warning: r.warning, same: same.map { SameTuning(id: $0.id.uuidString, name: $0.name) },
                                roots: [7, 2, 4, 9, 0, 5, 11].map { formatter.string(NoteName.simpleSpelling(ofPitchClass: $0, preferFlats: false)) })
        }

        // MARK: Editor «Сохранить изменения?»

        struct ChangeParams: Decodable { var original: Tuning; var draft: Tuning }
        struct ChangeResult: Encodable { var message: String; var match: String?; var matchId: String? }
        register("instrument.change", ChangeParams.self) { [unowned self] p in
            let c = TuningChange(original: p.original, draft: p.draft, instrument: instrument, formatter: formatter)
            return ChangeResult(message: c.message, match: c.match,
                                matchId: TuningTemplates.matching(p.draft.coursePitches, instrument: instrument)?.id)
        }

        /// `-tuningsDemo`: the five tunings of the canvas boards on the current instrument (Стандарт E, Drop D,
        /// «Полтона ниже» with sharps, DADGAD, Open G) → the instrument.
        register("instrument.demo") { [unowned self] _ in
            var inst = instrument
            let t = { (id: String) in TuningTemplates.template(id: id)!.makeTuning() }
            let standard = inst.currentTuning ?? t("g6-standard-e")
            var half = standard.shifted(bySemitones: -1)
            half.id = UUID(); half.name = "Полтона ниже"; half.accidentalPreference = .sharp; half.templateId = nil
            inst.tunings = [standard, t("g6-drop-d"), half, t("g6-dadgad"), t("g6-open-g")]
            inst.currentTuningId = standard.id
            return inst
        }

        // MARK: Template card

        struct IdParams: Decodable { var id: String }
        struct CardString: Encodable { var number: Int; var note: String; var hz: Double }
        struct Card: Encodable {
            var name: String
            var chip: String
            var strings: [CardString]
            var intervals: String
            var usage: String
        }
        /// Template card: strings with Hz (at the default A4), «кварты, B3 — терция», where it is used.
        register("instrument.templateCard", IdParams.self) { [unowned self] p in
            guard let t = TuningTemplates.template(id: p.id) else { throw BridgeError("no template \(p.id)") }
            let n = t.courseCount
            let type = Inst.typeName(t.type)
            let strings = t.notes.enumerated().map { index, note in
                CardString(number: n - index, note: formatter.string(note),
                           hz: 440 * pow(2, Double(note.midi - 69) / 12) * defaultA4 / 440)
            }
            // Intervals.
            let steps = zip(t.notes.dropFirst(), t.notes).map { $0.midi - $1.midi }
            let names = [3: "м. терция", 4: "терция", 5: "кварта", 7: "квинта", 2: "секунда", 12: "октава"]
            let common = Dictionary(grouping: steps, by: { $0 }).max { $0.value.count < $1.value.count }?.key ?? 5
            var parts = [common == 5 ? "кварты" : (names[common].map { $0 + "ы" } ?? "\(common) полутонов")]
            for (i, s) in steps.enumerated() where s != common {
                parts.append("\(formatter.string(t.notes[i + 1])) — \(names[s] ?? "\(s) полутонов")")
            }
            // Usage.
            let usage: String
            if t.id.contains("standard") {
                usage = "стандарт для \(n)-струнной \(type == "гитара" ? "гитары" : type)"
            } else if t.id.contains("drop") {
                usage = "дроп-строй: нижняя струна на тон ниже"
            } else {
                usage = "\(n) \(Inst.plural(n, "струна", "струны", "струн")) · \(type)"
            }
            return Card(name: t.names.ru, chip: "\(n) \(Inst.plural(n, "струна", "струны", "струн")) · \(type)", strings: strings,
                        intervals: parts.joined(separator: ", "), usage: usage)
        }

        // MARK: Generator

        struct GeneratorParams: Decodable { var strings: Int?; var lowestMIDI: Int?; var drop: Bool }
        struct NoteOption: Encodable { var midi: Int; var name: String }
        struct Existing: Encodable { var id: String; var name: String }
        struct GeneratedResult: Encodable {
            var notes: [String]
            var name: String
            var numbered: Bool
            var existing: Existing?
            /// The tuning to save when `count` equals the instrument's courses (pairing kept per course).
            var tuning: Tuning?
        }
        struct Generator: Encodable {
            var typeName: String
            var hasTemplate: Bool
            var courses: Int
            var count: Int
            var midi: Int
            var lowestName: String
            var options: [NoteOption]
            var result: GeneratedResult?
        }
        /// «Генератор строя»: type, strings (default: the instrument's), lowest standard note (default: the current
        /// tuning's), Drop → preview, unique name, an existing tuning with the same pitches.
        register("instrument.generator", GeneratorParams.self) { [unowned self] p in
            let type = instrument.type
            let count = p.strings ?? instrument.courses.count
            let midi = p.lowestMIDI ?? (tuning.coursePitches.first?.nearestMIDI ?? 40)
            func noteName(_ m: Int) -> String {
                formatter.string(SpelledNote(NoteName.simpleSpelling(ofPitchClass: m % 12, preferFlats: false), midi: m))
            }
            var out = Generator(typeName: Inst.typeName(type), hasTemplate: type.intervalTemplate != nil,
                                courses: instrument.courses.count, count: count, midi: midi, lowestName: noteName(midi),
                                options: (18...64).reversed().map { NoteOption(midi: $0, name: noteName($0)) }, result: nil)
            if let r = TuningGenerator.generate(type: type, stringCount: count, lowestStandard: Pitch(midi: Double(midi)), drop: p.drop) {
                let base = r.name.text(language: .ru, formatter: formatter)
                let (name, numbered) = uniqueName(base)
                let same = instrument.tunings.first { t in
                    t.openCents.count == r.pitches.count && zip(t.openCents, r.pitches).allSatisfy { abs($0[0] - $1.cents) < 1 }
                }
                var tuningToSave: Tuning?
                if count == instrument.courses.count {
                    tuningToSave = Tuning(name: name, openCents: zip(r.pitches, instrument.courses).map { pitch, course in
                        course.pairing == .octave ? [pitch.cents, pitch.cents + 1200]
                            : Array(repeating: pitch.cents, count: course.strings.count)
                    })
                }
                out.result = GeneratedResult(notes: r.notes.map { formatter.string($0) }, name: name, numbered: numbered,
                                             existing: same.map { Existing(id: $0.id.uuidString, name: $0.name) }, tuning: tuningToSave)
            }
            return out
        }

        // MARK: Instrument edits

        struct RebuildParams: Decodable { var count: Int; var high: Bool }
        struct RebuildRow: Encodable { var name: String; var change: String }
        struct Rebuild: Encodable {
            var rows: [RebuildRow]
            var warning: String?
            var instrument: Instrument
        }
        /// «N струн вместо M»: the rebuilt instrument, affected tunings with the added note, the low-range warning.
        register("instrument.rebuild", RebuildParams.self) { [unowned self] p in
            guard p.count >= 1 else { throw BridgeError("count \(p.count)") }
            let old = instrument.courses.count
            let preview = InstrumentEditing.changingStringCount(of: instrument, to: p.count, side: p.high ? .high : .low).0
            func chromatic(_ cents: Double) -> String {
                let pitch = Pitch(cents: cents)
                let flats = tuning.spelledNotes.contains { $0.name.accidental < 0 }
                return formatter.string(SpelledNote(NoteName.simpleSpelling(ofPitchClass: pitch.pitchClass, preferFlats: flats),
                                                    midi: pitch.nearestMIDI))
            }
            let rows = preview.tunings.map { t -> RebuildRow in
                guard p.count > old else { return RebuildRow(name: t.name, change: "− струна") }
                let index = p.high ? t.openCents.count - 1 : 0
                guard let cents = t.openCents[safe: index]?.first else { return RebuildRow(name: t.name, change: "") }
                return RebuildRow(name: t.name, change: "+ " + chromatic(cents))
            }
            var warning: String?
            if let lowest = preview.tunings.flatMap({ $0.openCents.compactMap(\.first) }).min() {
                let f = Pitch(cents: lowest).frequency(a4: defaultA4)
                if f < 33 { warning = "\(chromatic(lowest)) ≈ \(Int(f.rounded())) Гц — нижняя граница тюнера" }
            }
            return Rebuild(rows: rows, warning: warning, instrument: preview)
        }

        /// «Сдвоенные курсы»: every course unison (on) or single (off).
        struct PairedParams: Decodable { var on: Bool }
        register("instrument.setPaired", PairedParams.self) { [unowned self] p in
            var inst = instrument
            for c in inst.courses.indices {
                inst = InstrumentEditing.changingPairing(of: inst, course: c, to: p.on ? .unison : .single).0
            }
            return inst
        }

        // MARK: Strings and fanned frets (PR-7)

        struct FanPreset: Encodable { var name: String; var multiscale: Multiscale }
        struct GaugeSet: Encodable { var name: String; var gauges: [Double] }
        struct Strings: Encodable {
            var fanPresets: [FanPreset]
            var fanPresetName: String?
            var sets: [GaugeSet]
            var currentSet: String?
            /// Scale length of each course in mm (rounded), lowest first — fanned or the single one.
            var scales: [Int]
        }
        /// «Струны»: typical fans and string sets for this instrument, which one is current, per-course scale.
        register("instrument.strings") { [unowned self] _ in
            let i = instrument
            let presets = Inst.fanPresets(for: i)
            let sets = Inst.gaugeSets(for: i)
            let gauges = i.courses.map { $0.strings.first?.gauge }
            let single = Int(i.courses.first?.strings.first?.scaleLength ?? Double(Inst.defaultScale(i)))
            return Strings(
                fanPresets: presets.map { FanPreset(name: $0.0, multiscale: $0.1) },
                fanPresetName: i.multiscale.flatMap { m in presets.first { $0.1 == m }?.0 },
                sets: sets.map { GaugeSet(name: $0.0, gauges: $0.1) },
                currentSet: sets.first { $0.1.map(Optional.some) == Array(gauges.reversed()) || $0.1.map(Optional.some) == gauges }?.0,
                scales: i.courses.indices.map { c in
                    i.multiscale.map { Int($0.scaleLength(course: c, courses: i.courses.count).rounded()) } ?? single
                })
        }

        /// Sets a fan (`{"multiscale": …}`) or the n-th typical fan (`{"preset": n}`) and writes each string's
        /// scale length too (tension calculator WS-1) → the instrument. Also the `-fan` launch argument.
        struct FanParams: Decodable { var multiscale: Multiscale?; var preset: Int? }
        register("instrument.applyFan", FanParams.self) { [unowned self] p in
            var inst = instrument
            if let n = p.preset {
                let presets = Inst.fanPresets(for: inst)
                guard presets.indices.contains(n) else { throw BridgeError("no fan preset \(n)") }
                inst.multiscale = presets[n].1
            } else if let m = p.multiscale {
                inst.multiscale = m
            } else {
                throw BridgeError("multiscale or preset")
            }
            let n = inst.courses.count
            if let m = inst.multiscale {
                for c in inst.courses.indices {
                    for s in inst.courses[c].strings.indices {
                        inst.courses[c].strings[s].scaleLength = m.scaleLength(course: c, courses: n).rounded()
                    }
                }
            }
            return inst
        }
    }

    fileprivate func uniqueName(_ base: String) -> (String, Bool) {
        let names = Set(instrument.tunings.map(\.name))
        guard names.contains(base) else { return (base, false) }
        var n = 2
        while names.contains("\(base) (\(n))") { n += 1 }
        return ("\(base) (\(n))", true)
    }
}

/// Labels and presets of the instrument sheets (iOS: statics of LibrarySheet, InstrumentSheet, InstrumentStringsSheet).
fileprivate enum Inst {
    /// Russian plural: 1 струна, 2 струны, 5 струн.
    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let n10 = n % 10, n100 = n % 100
        if n10 == 1 && n100 != 11 { return one }
        if (2...4).contains(n10) && !(12...14).contains(n100) { return few }
        return many
    }

    static func typeName(_ type: InstrumentType) -> String {
        switch type {
        case .guitar, .guitarExtendedHigh: return "гитара"
        case .bass: return "бас"
        case .ukulele: return "укулеле"
        case .mandolin: return "мандолина"
        case .dutar: return "дутар"
        case .tanbur: return "танбур"
        case .rubob: return "рубоб"
        }
    }

    static func defaultScale(_ i: Instrument) -> Int {
        switch i.type {
        case .bass: return 864
        case .ukulele: return 330
        case .mandolin: return 350
        default: return i.courses.count >= 8 ? 686 : 648
        }
    }

    /// Fans of common extended-range guitars and basses (inches, neutral fret).
    static func fanPresets(for i: Instrument) -> [(String, Multiscale)] {
        let list: [(Double, Double, Int)]
        if i.type == .bass {
            list = [(35, 34, 7), (37, 34, 8), (35.5, 33.5, 7)]
        } else {
            switch i.courses.count {
            case ...6: list = [(25.5, 25, 7), (26.5, 25.5, 7), (25.5, 24.75, 7)]
            case 7: list = [(26.5, 25.5, 7), (27, 25.5, 8), (26.25, 25.5, 7)]
            case 8: list = [(27, 25.5, 7), (28, 25.5, 9), (27.2, 25.5, 8)]
            default: list = [(28, 25.5, 8), (28.6, 25.5, 9), (30, 26.5, 9)]
            }
        }
        return list.map { b, t, n in ("\(inchText(b))–\(inchText(t)) · \(n)-й", Multiscale.inches(b, t, neutralFret: n)) }
    }

    /// `%g″`: «27″», «25.5″», «24.75″».
    static func inchText(_ v: Double) -> String {
        v == v.rounded() ? "\(Int(v))″" : "\(v)″"
    }

    /// Common sets, from the lowest string.
    static func gaugeSets(for i: Instrument) -> [(String, [Double])] {
        switch (i.type, i.courses.count) {
        case (.guitar, 6), (.guitarExtendedHigh, 6):
            return [("D'Addario 10–46", [0.046, 0.036, 0.026, 0.017, 0.013, 0.010]), ("D'Addario 11–49", [0.049, 0.038, 0.028, 0.018, 0.014, 0.011])]
        case (.guitar, 7), (.guitarExtendedHigh, 7):
            return [("D'Addario 10–59", [0.059, 0.046, 0.036, 0.026, 0.017, 0.013, 0.010])]
        case (.guitar, 8), (.guitarExtendedHigh, 8):
            return [("D'Addario 10–74", [0.074, 0.062, 0.052, 0.042, 0.030, 0.017, 0.013, 0.010])]
        case (.guitar, 9), (.guitarExtendedHigh, 9):
            return [("Kalium 9-str 10–90", [0.090, 0.072, 0.059, 0.049, 0.038, 0.028, 0.017, 0.013, 0.010])]
        case (.bass, 4): return [("D'Addario 45–105", [0.105, 0.085, 0.065, 0.045])]
        case (.bass, 5): return [("D'Addario 45–130", [0.130, 0.105, 0.085, 0.065, 0.045])]
        default: return []
        }
    }
}
