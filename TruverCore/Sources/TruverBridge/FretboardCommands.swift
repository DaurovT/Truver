#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import TruverDSP
import TruverTheory

/// Bridge commands of the Fretboard feature (Flutter: lib/features/fretboard/…). Method names: "fretboard.<name>"
/// and "progression.<name>". Everything `FretboardController.swift` / `ProgressionController.swift` compute with the
/// core lives here; the DTOs carry ready labels in the session notation (as `app.formatter` / `chromaticName` on iOS).

// MARK: DTOs

struct SpotDTO: Codable { var course: Int; var fret: Int }

/// A note on the neck with its degree in the shown scale (or chord) and the plain chromatic name («F♯», no octave).
struct FretNoteDTO: Encodable {
    var course: Int
    var fret: Int
    var cents: Double
    var degree: Int
    var plain: String
}

struct PositionDTO: Encodable {
    var number: Int
    var notes: [FretNoteDTO]
    var fingers: [Int]
    var lo: Int
    var hi: Int
    var isTruncated: Bool
}

struct DegreeDTO: Encodable {
    var label: String
    var number: Int
    var semitones: Int
    var role: String
}

struct NamedNoteDTO: Encodable {
    var name: NoteName
    var text: String
}

/// One playable cell of the neck: its degree in the scale (nil — not a scale note) and the name the neck shows
/// (the scale's spelling, or the simple spelling with the scale's accidental family).
struct CellDTO: Encodable {
    var course: Int
    var fret: Int
    var cents: Double
    var degree: Int?
    var name: String
    /// `chromaticName` without the octave.
    var plain: String
}

struct KeyChordDTO: Encodable {
    /// In `chordFormatter` (letters in solfège), not compacted.
    var name: String
    /// In the app's formatter (accessibility).
    var spoken: String
    var roman: String
    var root: NoteName
    var pitchClasses: [Int]
    var chordId: String?
}

struct FanDTO: Encodable { var ratios: [Double]; var neutralFret: Int }

struct ScaleInfoDTO: Encodable {
    var id: String
    var name: String
    var category: String
    var count: Int
    var isUser: Bool
    var degrees: [DegreeDTO]
    var semitones: [Int]
}

struct ScaleDTO: Encodable {
    var scale: ScaleInfoDTO
    var tonic: NoteName
    var tonicText: String
    /// «E · Фригийский доминант» (solfège: «ми · фригийский доминант»).
    var title: String
    var spelled: [NoteName]
    var spelledText: [String]
    var spelledShort: [String]
    var flats: Bool
    var positions: [PositionDTO]
    var cells: [CellDTO]
    var triads: [KeyChordDTO]?
    var sevenths: [KeyChordDTO]?
    /// Library chord id of the key's triad on each degree (FB-21 default type).
    var triadIds: [String?]?
    /// The «Гамма» sheet's tonic grid: the preferred spelling of each pitch class 0…11 for this scale.
    var tonics: [NamedNoteDTO]
    var fan: FanDTO?
}

struct ChordToneDTO: Encodable { var pc: Int; var text: String; var name: NoteName }
struct ChordDegreeDTO: Encodable { var label: String; var number: Int; var semitones: Int; var labelJSON: DegreeLabel }

struct ChordDTO: Encodable {
    var id: String
    var symbol: String
    /// `chord.name(root:formatter:)`, not compacted.
    var name: String
    var rootText: String
    var degrees: [ChordDegreeDTO]
    var tones: [ChordToneDTO]
}

struct VoicingNoteDTO: Encodable {
    var course: Int
    var fret: Int
    var cents: Double
    var pc: Int
    /// `chromaticName` with the octave, and without it.
    var chroma: String
    var plain: String
}

struct VoicingDTO: Encodable {
    var frets: [Int?]
    var notes: [VoicingNoteDTO]
    var fingers: Int
    var barreFret: Int?
    var span: Int
    var lowestFret: Int
    var usesOpenStrings: Bool
    var isStretch: Bool
    var cost: Double
    /// Finger per course (−1 = none), `ChordVoicing.fingerNumbers`.
    var fingerNumbers: [Int]
}

struct VoicingsDTO: Encodable {
    var chord: ChordDTO
    var voicings: [VoicingDTO]
    var omissionHint: DegreeLabel?
}

struct MatchDTO: Encodable {
    /// `ChordMatch.name(formatter:)`, not compacted.
    var name: String
    var root: NoteName
    var chordId: String
    var bass: Int?
    /// The chord's tones in the app's notation, «A C E G».
    var tones: String
    /// Sheet «Отмечено 4 ноты» (canvas 2026-11-25): the chord name without the bass (chord formatter), the bass in
    /// the notation, the tones one by one with whether they were marked.
    var chordOnly: String = ""
    var bassName: String?
    var toneList: [MatchToneDTO] = []
}

struct MatchToneDTO: Encodable {
    var name: String
    var pc: Int
    var missing: Bool
}

struct ScaleMatchDTO: Encodable {
    var tonic: NoteName
    var scaleId: String
    /// «E фригийский доминант».
    var title: String
}

extension Bridge {
    var board: Fretboard? { Fretboard(instrument: instrument) }

    /// Chord symbols: letters in solfège (AppModel.chordFormatter).
    var chordFormatter: NoteFormatter {
        NoteFormatter(notation: notation == .solfege ? .international : notation, language: .ru)
    }

    /// `AppModel.chromaticName(_:)`: the nearest note with the tuning's accidental family, with the octave.
    func chromatic(_ pitch: Pitch) -> String {
        let flats = tuning.spelledNotes.contains { $0.name.accidental < 0 }
        return formatter.string(SpelledNote(NoteName.simpleSpelling(ofPitchClass: pitch.pitchClass, preferFlats: flats),
                                            midi: pitch.nearestMIDI))
    }

    /// `chromaticName(pitch).filter { !$0.isNumber }`.
    func plain(_ pitch: Pitch) -> String { chromatic(pitch).filter { !$0.isNumber } }

    func fretNoteDTO(_ n: FretNote) -> FretNoteDTO {
        FretNoteDTO(course: n.course, fret: n.fret, cents: n.pitch.cents, degree: n.degreeIndex, plain: plain(n.pitch))
    }

    func positionDTO(_ p: ScalePosition) -> PositionDTO {
        PositionDTO(number: p.number, notes: p.notes.map(fretNoteDTO), fingers: p.fingers, lo: p.fretRange.lowerBound,
                    hi: p.fretRange.upperBound, isTruncated: p.isTruncated)
    }

    func scaleInfo(_ scale: Scale) -> ScaleInfoDTO {
        ScaleInfoDTO(id: scale.id, name: scale.names.ru, category: scale.category.rawValue, count: scale.count,
                     isUser: scale.isUserDefined,
                     degrees: scale.degrees.indices.map { i in
                         DegreeDTO(label: scale.degrees[i].label.description, number: scale.degrees[i].label.number,
                                   semitones: scale.degrees[i].semitones, role: scale.role(ofDegree: i).rawValue)
                     },
                     semitones: scale.degrees.map(\.semitones))
    }

    func keyChordDTO(_ c: KeyChord) -> KeyChordDTO {
        KeyChordDTO(name: c.name(formatter: chordFormatter), spoken: c.name(formatter: formatter), roman: c.romanNumeral,
                    root: c.root, pitchClasses: c.notes.map(\.pitchClass), chordId: c.chord?.id)
    }

    func voicingDTO(_ v: ChordVoicing) -> VoicingDTO {
        let fingers = v.fingerNumbers
        return VoicingDTO(frets: v.frets,
                          notes: v.notes.map { n in
                              VoicingNoteDTO(course: n.course, fret: n.fret, cents: n.pitch.cents, pc: n.pitch.pitchClass,
                                             chroma: chromatic(n.pitch), plain: plain(n.pitch))
                          },
                          fingers: v.fingers, barreFret: v.barreFret, span: v.span, lowestFret: v.lowestFret,
                          usesOpenStrings: v.usesOpenStrings, isStretch: v.isStretch, cost: v.cost,
                          fingerNumbers: v.frets.indices.map { fingers[$0] ?? -1 })
    }

    func chordDTO(_ chord: Chord, root: NoteName) -> ChordDTO {
        let spelled = chord.spell(root: root)
        return ChordDTO(id: chord.id, symbol: chord.symbol, name: chord.name(root: root, formatter: formatter),
                        rootText: formatter.string(root),
                        degrees: chord.degrees.map { ChordDegreeDTO(label: $0.label.description, number: $0.label.number,
                                                                    semitones: $0.semitones, labelJSON: $0.label) },
                        tones: spelled.map { ChordToneDTO(pc: $0.pitchClass, text: formatter.string($0), name: $0) })
    }

    func scaleMatchDTO(_ m: ScaleMatch) -> ScaleMatchDTO {
        ScaleMatchDTO(tonic: m.tonic, scaleId: m.scale.id, title: formatter.string(m.tonic) + " " + m.scale.names.ru.lowercased())
    }

    func matchDTO(_ m: ChordMatch) -> MatchDTO {
        let missing = Set(m.missing.map(\.pitchClass))
        return MatchDTO(name: m.name(formatter: formatter), root: m.root, chordId: m.chord.id, bass: m.bass?.pitchClass,
                        tones: m.chord.spell(root: m.root).map { formatter.string($0) }.joined(separator: " "),
                        chordOnly: m.chord.name(root: m.root, formatter: chordFormatter),
                        bassName: m.bass.map { formatter.string($0) },
                        toneList: m.chord.spell(root: m.root).map { MatchToneDTO(name: formatter.string($0), pc: $0.pitchClass, missing: missing.contains($0.pitchClass)) })
    }

    static func layoutOptions(_ open: Bool?, _ pattern: EightNotePattern?) -> LayoutOptions {
        LayoutOptions(allowOpenStrings: open ?? true, eightNotePattern: pattern ?? .threeThreeTwo)
    }

    func registerFretboard() {
        struct ScaleParams: Decodable {
            var scaleId: String
            var tonic: NoteName
            var layout: LayoutKind
            var allowOpenStrings: Bool?
            var eightNotePattern: EightNotePattern?
        }
        /// Everything the scale view needs: spelling, positions, every playable cell, key chords, tonic grid, fan.
        register("fretboard.scale", ScaleParams.self) { [unowned self] p in
            let scale = ScaleLibrary.scale(id: p.scaleId) ?? ScaleLibrary.major
            let spelled = ScaleSpeller.spell(scale, tonic: p.tonic)
            let flats = spelled.contains { $0.accidental < 0 }
            let name = notation == .solfege ? scale.names.ru.lowercased() : scale.names.ru
            var positions: [PositionDTO] = []
            var cells: [CellDTO] = []
            var fan: FanDTO?
            if let fb = board {
                positions = PositionLayout.positions(p.layout, scale: scale, tonic: p.tonic, on: fb,
                                                     options: Self.layoutOptions(p.allowOpenStrings, p.eightNotePattern)).map(positionDTO)
                for course in 0..<fb.courseCount {
                    for fret in instrument.playableFrets(course: course) {
                        guard let pitch = fb.pitch(course: course, fret: fret) else { continue }
                        let degree = scale.degreeIndex(of: pitch, tonic: p.tonic)
                        let text = degree.map { formatter.string(spelled[$0]) }
                            ?? formatter.string(NoteName.simpleSpelling(ofPitchClass: pitch.pitchClass, preferFlats: flats))
                        cells.append(CellDTO(course: course, fret: fret, cents: pitch.cents, degree: degree, name: text, plain: plain(pitch)))
                    }
                }
                if let m = instrument.multiscale, m.bassScaleLength != m.trebleScaleLength, fb.courseCount > 1 {
                    fan = FanDTO(ratios: m.ratios(courses: fb.courseCount), neutralFret: m.neutralFret)
                }
            }
            let triads = KeyChords.triads(scale, tonic: p.tonic)
            return ScaleDTO(scale: scaleInfo(scale), tonic: p.tonic, tonicText: formatter.string(p.tonic),
                            title: "\(formatter.string(p.tonic)) · \(name)", spelled: spelled,
                            spelledText: spelled.map { formatter.string($0) }, spelledShort: spelled.map { formatter.short($0) },
                            flats: flats, positions: positions, cells: cells,
                            triads: triads?.map(keyChordDTO),
                            sevenths: KeyChords.sevenths(scale, tonic: p.tonic)?.map(keyChordDTO),
                            triadIds: triads?.map { $0.chord?.id },
                            tonics: (0..<12).map { pc in
                                let n = ScaleSpeller.preferredTonic(pitchClass: pc, scale: scale)
                                return NamedNoteDTO(name: n, text: formatter.string(n))
                            },
                            fan: fan)
        }

        /// FB-25 «Гамма от ноты»: the position starting on a cell; `tonic` nil — the preferred spelling of the cell.
        struct FromParams: Decodable {
            var scaleId: String
            var tonic: NoteName?
            var layout: LayoutKind
            var allowOpenStrings: Bool?
            var eightNotePattern: EightNotePattern?
            var course: Int
            var fret: Int
        }
        struct FromDTO: Encodable {
            var tonic: NoteName
            var tonicText: String
            var scale: ScaleInfoDTO
            var spelledText: [String]
            var position: PositionDTO?
        }
        register("fretboard.positionFrom", FromParams.self) { [unowned self] p in
            guard let fb = board, let pitch = fb.pitch(course: p.course, fret: p.fret) else { throw BridgeError("no cell") }
            let scale = ScaleLibrary.scale(id: p.scaleId) ?? ScaleLibrary.major
            let tonic = p.tonic ?? ScaleSpeller.preferredTonic(pitchClass: pitch.pitchClass, scale: scale)
            let position = PositionLayout.position(from: (p.course, p.fret), kind: p.layout, scale: scale, tonic: tonic, on: fb,
                                                   options: Self.layoutOptions(p.allowOpenStrings, p.eightNotePattern))
            return FromDTO(tonic: tonic, tonicText: formatter.string(tonic), scale: scaleInfo(scale),
                           spelledText: ScaleSpeller.spell(scale, tonic: tonic).map { formatter.string($0) },
                           position: position.map(positionDTO))
        }

        /// FB-20 path; `start` nil — the lowest tonic on the lowest string.
        struct PathParams: Decodable {
            var kind: PathKind
            var scaleId: String
            var tonic: NoteName
            var start: SpotDTO?
        }
        struct PathDTO: Encodable {
            var notes: [FretNoteDTO]
            /// `chromaticName` of the first note, with the octave.
            var firstName: String
        }
        register("fretboard.path", PathParams.self) { [unowned self] p in
            guard let fb = board else { return PathDTO(notes: [], firstName: "") }
            let scale = ScaleLibrary.scale(id: p.scaleId) ?? ScaleLibrary.major
            var start = p.start.map { ($0.course, $0.fret) }
            if start == nil {
                for fret in 0...fb.instrument.fretCount {
                    if let pitch = fb.pitch(course: 0, fret: fret), pitch.pitchClass == p.tonic.pitchClass { start = (0, fret); break }
                }
            }
            guard let start else { return PathDTO(notes: [], firstName: "") }
            let notes = ScalePath.build(p.kind, scale: scale, tonic: p.tonic, on: fb, start: start)
            return PathDTO(notes: notes.map(fretNoteDTO), firstName: notes.first.map { chromatic($0.pitch) } ?? "")
        }

        /// FB-9 / FB-21 voicings of a chord; the omission hint when nothing fits.
        struct VoicingParams: Decodable {
            var chordId: String
            var root: NoteName
            var omitted: [DegreeLabel]?
            var bass: Int?
            var anchor: SpotDTO?
            var limit: Int?
            var within: [Int]?
        }
        register("fretboard.voicings", VoicingParams.self) { [unowned self] p in
            let base = ChordLibrary.anyChord(id: p.chordId) ?? ChordLibrary.minor7
            let omitted = Set(p.omitted ?? [])
            let chord = omitted.isEmpty ? base : base.omitting(omitted)
            guard let fb = board else { return VoicingsDTO(chord: chordDTO(chord, root: p.root), voicings: [], omissionHint: nil) }
            let anchor = p.anchor.map { ($0.course, $0.fret) }
            let within = p.within.flatMap { $0.count == 2 && $0[0] <= $0[1] ? $0[0]...$0[1] : nil }
            let list = ChordVoicings.voicings(chord: chord, root: p.root, on: fb, bassPitchClass: p.bass, anchor: anchor,
                                              limit: p.limit ?? 30, within: within)
            let hint = list.isEmpty ? ChordVoicings.omissionHint(chord: chord, root: p.root, on: fb, anchor: anchor, knownEmpty: true) : nil
            return VoicingsDTO(chord: chordDTO(chord, root: p.root), voicings: list.map(voicingDTO), omissionHint: hint)
        }

        /// Names of several chord types on one root (chips of «Аккорды от ноты»).
        struct NamesParams: Decodable { var root: NoteName; var ids: [String] }
        struct NameDTO: Encodable { var id: String; var name: String }
        register("fretboard.chordNames", NamesParams.self) { [unowned self] p in
            p.ids.compactMap { id in ChordLibrary.anyChord(id: id).map { NameDTO(id: id, name: $0.name(root: p.root, formatter: formatter)) } }
        }

        /// FB-17 tap on a key chord: a real shape near the visible frets (or one chord tone per string).
        struct StrumParams: Decodable {
            var root: NoteName
            var chordId: String?
            var pitchClasses: [Int]
            var lo: Int
            var hi: Int
        }
        struct StrumNoteDTO: Encodable { var course: Int; var cents: Double }
        register("fretboard.strum", StrumParams.self) { [unowned self] p in
            guard let fb = board else { return [StrumNoteDTO]() }
            let range = p.lo...max(p.lo, p.hi)
            var voicing: [(course: Int, pitch: Pitch)] = []
            if let id = p.chordId, let type = ChordLibrary.anyChord(id: id) {
                let around = range.count > 14 ? 0...12 : max(1, range.lowerBound - 1)...range.upperBound
                let centre = Double(around.lowerBound + around.upperBound) / 2
                let shapes = ChordVoicings.voicings(chord: type, root: p.root, on: fb, limit: 24, within: around)
                let best = shapes.min { a, b in
                    func score(_ v: ChordVoicing) -> Double {
                        let fretted = v.notes.filter { $0.fret > 0 }.map { Double($0.fret) }
                        let c = fretted.isEmpty ? centre : fretted.reduce(0, +) / Double(fretted.count)
                        return v.cost * 0.3 + abs(c - centre) * 0.4
                    }
                    return score(a) < score(b)
                }
                if let best { voicing = best.notes.map { ($0.course, $0.pitch) } }
            }
            if voicing.isEmpty {
                let classes = Set(p.pitchClasses)
                for course in 0..<instrument.courses.count {
                    let frets = instrument.playableFrets(course: course).filter { range.contains($0) }
                    if let fret = frets.first(where: { fb.pitch(course: course, fret: $0).map { classes.contains($0.pitchClass) } ?? false }),
                       let pitch = fb.pitch(course: course, fret: fret) {
                        voicing.append((course, pitch))
                    }
                }
            }
            return voicing.map { StrumNoteDTO(course: $0.course, cents: $0.pitch.cents) }
        }

        /// FB-10 «Поиск»: chords and scales of the marked notes.
        struct SearchParams: Decodable { var marked: [SpotDTO]; var preferFlats: Bool }
        struct PitchDTO: Encodable { var cents: Double; var plain: String }
        struct NearestDTO: Encodable { var match: MatchDTO; var matched: Int }
        struct SearchDTO: Encodable {
            var pitches: [PitchDTO]
            var distinct: Int
            var chords: [MatchDTO]
            var scales: [ScaleMatchDTO]
            var nearest: NearestDTO?
        }
        register("fretboard.search", SearchParams.self) { [unowned self] p in
            let pitches = p.marked.compactMap { board?.pitch(course: $0.course, fret: $0.fret) }.sorted { $0.cents < $1.cents }
            let pcs = Set(pitches.map(\.pitchClass))
            var chords: [MatchDTO] = [], scales: [ScaleMatchDTO] = [], nearest: NearestDTO?
            if pitches.count >= 3 {
                chords = ChordRecognizer.identify(pitchClasses: pcs, bass: pitches.first?.pitchClass, preferFlats: p.preferFlats).map(matchDTO)
                scales = ScaleFinder.scales(containing: pcs, preferredTonic: pitches.first?.pitchClass).map(scaleMatchDTO)
                if chords.isEmpty, let n = ChordRecognizer.nearest(pitchClasses: pcs, bass: pitches.first?.pitchClass) {
                    nearest = NearestDTO(match: matchDTO(n.match), matched: n.matched)
                }
            }
            return SearchDTO(pitches: pitches.map { PitchDTO(cents: $0.cents, plain: plain($0)) }, distinct: pcs.count,
                             chords: chords, scales: scales, nearest: nearest)
        }

        /// FB-9 «Подходящие гаммы» of a chord.
        struct ScalesParams: Decodable { var pitchClasses: [Int]; var preferredTonic: Int?; var limit: Int? }
        register("fretboard.scalesContaining", ScalesParams.self) { [unowned self] p in
            ScaleFinder.scales(containing: Set(p.pitchClasses), preferredTonic: p.preferredTonic, limit: p.limit ?? 12).map(scaleMatchDTO)
        }

        /// The scale and chord libraries (with the user's own) for the sheets.
        struct LibScaleDTO: Encodable {
            var id: String
            var name: String
            var category: String
            var needsReview: Bool
            var isUser: Bool
            var labels: String
        }
        struct LibChordDTO: Encodable { var id: String; var symbol: String; var isUser: Bool }
        struct LibraryDTO: Encodable { var scales: [LibScaleDTO]; var chords: [LibChordDTO] }
        register("fretboard.library") { _ in
            LibraryDTO(scales: ScaleLibrary.allWithUser.map { s in
                           LibScaleDTO(id: s.id, name: s.names.ru, category: s.category.rawValue, needsReview: s.needsReview,
                                       isUser: s.isUserDefined, labels: s.degrees.map(\.label.description).joined(separator: " "))
                       },
                       chords: ChordLibrary.full.map { LibChordDTO(id: $0.id, symbol: $0.symbol, isUser: $0.isUserDefined) })
        }

        struct QueryParams: Decodable { var query: String }
        register("fretboard.scaleSearch", QueryParams.self) { p in ScaleLibrary.search(p.query).map(\.id) }

        /// The note menu and the «… от ноты» sheets: names and degree of a cell, the mode of the scale from it.
        struct NoteParams: Decodable { var course: Int; var fret: Int; var scaleId: String; var tonic: NoteName }
        struct NoteInfoDTO: Encodable {
            var cents: Double
            var pc: Int
            var chroma: String
            var plain: String
            var degree: Int?
            var degreeLabel: String?
            /// `FretboardController.noteName(_:)`: the scale's short spelling, chromatic outside the scale.
            var short: String
            /// `ScaleSpeller.preferredTonic(…, scale: major)` — the root of «Аккорды от ноты».
            var majorRoot: NoteName
            var majorRootText: String
            /// The mode of the current scale starting on this note.
            var modeId: String?
            var modeName: String?
            /// The key's triad on this degree.
            var triadId: String?
        }
        register("fretboard.noteInfo", NoteParams.self) { [unowned self] p in
            guard let fb = board, let pitch = fb.pitch(course: p.course, fret: p.fret) else { throw BridgeError("no cell") }
            let scale = ScaleLibrary.scale(id: p.scaleId) ?? ScaleLibrary.major
            let degree = scale.degreeIndex(of: pitch, tonic: p.tonic)
            let spelled = ScaleSpeller.spell(scale, tonic: p.tonic)
            let short = degree.flatMap { spelled.indices.contains($0) ? formatter.short(spelled[$0]) : nil } ?? plain(pitch)
            let root = ScaleSpeller.preferredTonic(pitchClass: pitch.pitchClass, scale: ScaleLibrary.major)
            let mode = ScaleLibrary.mode(of: scale, tonic: p.tonic, startingOn: pitch.pitchClass)
            let triad = degree.flatMap { KeyChords.triads(scale, tonic: p.tonic)?[safe: $0]?.chord?.id }
            return NoteInfoDTO(cents: pitch.cents, pc: pitch.pitchClass, chroma: chromatic(pitch), plain: plain(pitch), degree: degree,
                               degreeLabel: degree.map { scale.degrees[$0].label.description }, short: short,
                               majorRoot: root, majorRootText: formatter.string(root), modeId: mode?.id, modeName: mode?.names.ru,
                               triadId: triad)
        }

        /// `ScaleSpeller.preferredTonic(pitchClass:scale:)`.
        struct TonicParams: Decodable { var pitchClass: Int; var scaleId: String }
        register("fretboard.preferredTonic", TonicParams.self) { [unowned self] p in
            let scale = ScaleLibrary.scale(id: p.scaleId) ?? ScaleLibrary.major
            let n = ScaleSpeller.preferredTonic(pitchClass: p.pitchClass, scale: scale)
            return NamedNoteDTO(name: n, text: formatter.string(n))
        }

        /// `NoteName.simpleSpelling(ofPitchClass:preferFlats:)` for several pitch classes, with names.
        struct SpellItem: Decodable { var pc: Int; var flats: Bool }
        struct SpellParams: Decodable { var items: [SpellItem] }
        register("fretboard.spellings", SpellParams.self) { [unowned self] p in
            p.items.map { item in
                let n = NoteName.simpleSpelling(ofPitchClass: item.pc, preferFlats: item.flats)
                return NamedNoteDTO(name: n, text: formatter.string(n))
            }
        }

        /// 5.2.1 rule 6: the other simple spelling of the tonic (G♯ ↔ A♭).
        struct EnharmonicParams: Decodable { var tonic: NoteName }
        register("fretboard.enharmonic", EnharmonicParams.self) { p in
            let options = NoteName.simpleSpellings(ofPitchClass: p.tonic.pitchClass).filter { $0 != p.tonic }
            return options.min { abs($0.accidental) < abs($1.accidental) } ?? p.tonic
        }

        /// FB-8 playing order of `count` notes.
        struct OrderParams: Decodable { var pattern: String; var direction: PlaybackDirection; var loop: Bool; var count: Int }
        register("fretboard.order", OrderParams.self) { p in
            let pattern: PlaybackPattern
            switch p.pattern {
            case "thirds": pattern = .thirds
            case "seq3": pattern = .sequence(groupSize: 3)
            case "seq4": pattern = .sequence(groupSize: 4)
            default: pattern = .up
            }
            return pattern.cycle(noteCount: p.count, direction: p.direction, loop: p.loop)
        }

        /// Debug `-fan`: the first typical fan of the instrument (InstrumentStringsSheet.fanPresets) and each course's
        /// scale length (`syncStrings`).
        struct FanPresetDTO: Encodable { var multiscale: Multiscale; var lengths: [Double] }
        register("fretboard.fanPreset") { [unowned self] _ in
            let i = instrument
            let preset: (Double, Double, Int)
            if i.type == .bass {
                preset = (35, 34, 7)
            } else {
                switch i.courses.count {
                case ...6: preset = (25.5, 25, 7)
                case 7: preset = (26.5, 25.5, 7)
                case 8: preset = (27, 25.5, 7)
                default: preset = (28, 25.5, 8)
                }
            }
            let m = Multiscale.inches(preset.0, preset.1, neutralFret: preset.2)
            let n = i.courses.count
            return FanPresetDTO(multiscale: m, lengths: (0..<n).map { m.scaleLength(course: $0, courses: n).rounded() })
        }

        registerUserTheory()
        registerProgression()
    }

    // MARK: TH-8 own scales and chords

    func registerUserTheory() {
        /// «Своя гамма»: the label and note of each of the 12 semitones as they would be named with this draft, the
        /// built-in twin, and the `Scale` to store.
        struct ScaleDraftParams: Decodable { var id: String; var name: String; var semitones: [Int]; var tonic: NoteName }
        struct StepDTO: Encodable { var label: String; var note: String }
        struct ScaleDraftDTO: Encodable { var steps: [StepDTO]; var twin: String?; var scale: Scale }
        register("fretboard.scaleDraft", ScaleDraftParams.self) { [unowned self] p in
            let steps = Set(p.semitones.map { (($0 % 12) + 12) % 12 }).union([0])
            let rows: [StepDTO] = (0..<12).map { semis in
                let scale = Scale.user(id: "draft", name: "", semitones: Array(steps.union([semis])))
                let label = scale.degrees.first { (($0.semitones % 12) + 12) % 12 == semis }?.label ?? DegreeLabel.common(semitones: semis)
                let note = NoteName.spelling(letter: p.tonic.letter.advanced(by: label.letterSteps), pitchClass: p.tonic.pitchClass + semis)
                return StepDTO(label: label.description, note: formatter.string(note))
            }
            let twin = ScaleLibrary.all.first { $0.semitoneSet == steps.sorted() && !$0.needsReview }
            return ScaleDraftDTO(steps: rows, twin: twin?.names.ru, scale: Scale.user(id: p.id, name: p.name, semitones: Array(steps)))
        }

        /// «Свой аккорд»: notes of the choice buttons, the auto symbol, the spelled chord, the built-in twin, the `Chord`.
        struct ChordDraftParams: Decodable { var id: String; var symbol: String; var labels: [DegreeLabel]; var root: NoteName; var choices: [DegreeLabel] }
        struct TwinDTO: Encodable { var symbol: String; var name: String }
        struct ChordDraftDTO: Encodable {
            var choiceNotes: [String]
            var autoSymbol: String
            var spelled: String
            var rootText: String
            var twin: TwinDTO?
            var chord: Chord
        }
        register("fretboard.chordDraft", ChordDraftParams.self) { [unowned self] p in
            let sorted = Chord.user(id: "draft", name: "", symbol: "", labels: p.labels).degrees.map(\.label)
            let auto = "(" + sorted.map(\.description).joined(separator: " ") + ")"
            var cut = Substring(p.symbol)
            while cut.first == " " { cut = cut.dropFirst() }
            while cut.last == " " { cut = cut.dropLast() }
            let trimmed = String(cut)
            let symbol = trimmed.isEmpty ? auto : trimmed
            let chord = Chord.user(id: p.id, name: symbol, symbol: symbol, labels: p.labels)
            let set = chord.intervalSet
            let twin = ChordLibrary.full.first { !$0.isUserDefined && $0.intervalSet == set }
            return ChordDraftDTO(
                choiceNotes: p.choices.map { label in
                    formatter.string(NoteName.spelling(letter: p.root.letter.advanced(by: label.letterSteps), pitchClass: p.root.pitchClass + label.semitones))
                },
                autoSymbol: auto,
                spelled: chord.spell(root: p.root).map { formatter.string($0) }.joined(separator: " "),
                rootText: formatter.string(p.root),
                twin: twin.map { TwinDTO(symbol: $0.symbol, name: $0.names.ru) },
                chord: chord)
        }
    }

    // MARK: Progression (FB-11, FB-22, FB-24)

    func registerProgression() {
        struct TemplateDTO: Encodable { var id: String; var name: String }
        struct ChordRowDTO: Encodable {
            var degree: Int
            var accidental: Int
            var chordId: String
            var bars: Int
            var numeral: String
            var root: NoteName
            /// `chord.name(root:formatter:)`, not compacted.
            var name: String
            var isMinor: Bool
        }
        struct VoicedDTO: Encodable {
            var root: NoteName
            var chordId: String
            var name: String
            /// In `chordFormatter` (letters in solfège).
            var letterName: String
            var chord: ChordDTO
            var voicing: VoicingDTO?
            var outOfWindow: Bool
        }
        struct StateDTO: Encodable {
            var templates: [TemplateDTO]
            var name: String
            var key: NoteName
            var keyText: String
            var chords: [ChordRowDTO]
            var voiced: [VoicedDTO]
        }
        struct StateParams: Decodable {
            var templateId: String
            var custom: [ProgressionChord]?
            var key: NoteName
            var window: [Int]?
            var anchor: SpotDTO?
            var loop: Bool
            /// Voice the chords (false — names only).
            var voice: Bool?
        }
        func progression(_ p: StateParams) -> Progression {
            let templates = ProgressionLibrary.all(key: p.key)
            let template = templates.first { $0.id == p.templateId } ?? templates[0]
            guard let custom = p.custom else { return template }
            return Progression(id: "custom", name: template.name, key: p.key, chords: custom)
        }
        func rows(_ prog: Progression) -> [ChordRowDTO] {
            let minor: Set<String> = ["m", "m7", "m7b5", "mmaj7", "m6", "m9", "m11", "madd9", "dim", "dim7"]
            return prog.chords.map { c in
                let root = c.root(in: prog.key)
                return ChordRowDTO(degree: c.degree, accidental: c.accidental, chordId: c.chordId, bars: c.bars, numeral: c.numeral,
                                   root: root, name: c.chord.name(root: root, formatter: formatter), isMinor: minor.contains(c.chordId))
            }
        }
        /// The library in a key, the progression's chords and their voice-led voicings.
        register("progression.state", StateParams.self) { [unowned self] p in
            let prog = progression(p)
            var voiced: [VoicedDTO] = []
            if p.voice ?? true, let fb = board {
                let window = p.window.flatMap { $0.count == 2 && $0[0] <= $0[1] ? $0[0]...$0[1] : nil }
                let result = ProgressionVoicer.voice(prog.symbols, on: fb, window: window, anchor: p.anchor.map { ($0.course, $0.fret) },
                                                     loop: p.loop)
                ProgressionCache.voiced = result
                ProgressionCache.alternatives = [:]
                voiced = result.map { v in
                    VoicedDTO(root: v.root, chordId: v.chord.id, name: v.chord.name(root: v.root, formatter: formatter),
                              letterName: v.chord.name(root: v.root, formatter: chordFormatter),
                              chord: chordDTO(v.chord, root: v.root), voicing: v.voicing.map(voicingDTO), outOfWindow: v.outOfWindow)
                }
            }
            return StateDTO(templates: ProgressionLibrary.all(key: p.key).map { TemplateDTO(id: $0.id, name: $0.name) },
                            name: prog.name, key: prog.key, keyText: formatter.string(prog.key), chords: rows(prog), voiced: voiced)
        }

        /// Other voicings of one chord (inside the window when there is one), most comfortable first.
        struct AltParams: Decodable { var index: Int?; var root: NoteName; var chordId: String; var window: [Int]? }
        register("progression.alternatives", AltParams.self) { [unowned self] p in
            guard let fb = board else { return [VoicingDTO]() }
            let chord = ChordLibrary.anyChord(id: p.chordId) ?? ChordLibrary.major
            let all = ChordVoicings.voicings(chord: chord, root: p.root, on: fb, limit: 40)
            var list = Array(all.prefix(16))
            if let w = p.window, w.count == 2, w[0] <= w[1] {
                let window = w[0]...w[1]
                let inside = all.filter { n in n.notes.allSatisfy { $0.fret == 0 || window.contains($0.fret) } }
                list = Array((inside.isEmpty ? all : inside).prefix(16))
            }
            if let index = p.index { ProgressionCache.alternatives[index] = list }
            return list.map(voicingDTO)
        }

        /// The chord a numeral stands for in a key (palette of «Заменить на» / «+»).
        struct PaletteParams: Decodable { var key: NoteName; var numerals: [String] }
        struct PaletteDTO: Encodable { var numeral: String; var chord: ProgressionChord; var name: String }
        register("progression.palette", PaletteParams.self) { [unowned self] p in
            p.numerals.compactMap { text in
                ProgressionChord(numeral: text).map { c in
                    PaletteDTO(numeral: c.numeral, chord: c, name: c.chord.name(root: c.root(in: p.key), formatter: chordFormatter))
                }
            }
        }

        /// «Любой аккорд»: a chord by root and type in the key.
        struct AnyParams: Decodable { var root: NoteName; var key: NoteName; var chordId: String; var bars: Int? }
        struct AnyDTO: Encodable { var chord: ProgressionChord; var name: String }
        register("progression.anyChord", AnyParams.self) { [unowned self] p in
            let c = ProgressionChord(root: p.root, in: p.key, chordId: p.chordId, bars: p.bars ?? 1)
            return AnyDTO(chord: c, name: (ChordLibrary.anyChord(id: p.chordId) ?? ChordLibrary.major).name(root: p.root, formatter: chordFormatter))
        }

        /// TH-7: the key moved by semitones with a simple spelling.
        struct TransposeParams: Decodable { var templateId: String; var custom: [ProgressionChord]?; var key: NoteName; var semitones: Int }
        register("progression.transpose", TransposeParams.self) { p in
            let templates = ProgressionLibrary.all(key: p.key)
            let template = templates.first { $0.id == p.templateId } ?? templates[0]
            let prog = p.custom.map { Progression(id: "custom", name: template.name, key: p.key, chords: $0) } ?? template
            return prog.transposed(bySemitones: p.semitones).key
        }

        /// FB-22 hand window around a fret.
        struct WindowParams: Decodable { var fret: Int; var fretCount: Int }
        register("progression.window", WindowParams.self) { p in
            let w = ProgressionVoicer.window(around: p.fret, fretCount: p.fretCount)
            return [w.lowerBound, w.upperBound]
        }

        /// FB-24 strokes of one pass over the chords of the last `progression.state` (calls are serialised by the
        /// bridge lock); `overrides` — voicings the user picked, as an index into that chord's `progression.alternatives`.
        struct ScheduleParams: Decodable {
            var overrides: [[Int]]?
            var chordBars: [Int]
            var barsPerChord: Int?
            var beatsPerBar: Int
            var bpm: Double
            var rhythm: StrumRhythm
            var countInBars: Int
        }
        struct EventNoteDTO: Encodable { var course: Int; var cents: Double; var offset: Double }
        struct EventDTO: Encodable { var time: Double; var notes: [EventNoteDTO]; var velocity: Double; var duration: Double }
        struct TimelineDTO: Encodable { var events: [EventDTO]; var chordStarts: [Double]; var countIn: Double; var cycle: Double }
        register("progression.schedule", ScheduleParams.self) { p in
            var voiced = ProgressionCache.voiced
            for pair in p.overrides ?? [] where pair.count == 2 && voiced.indices.contains(pair[0]) {
                let index = pair[0], alt = pair[1]
                if let list = ProgressionCache.alternatives[index], list.indices.contains(alt) {
                    voiced[index].voicing = list[alt]
                    voiced[index].outOfWindow = false
                }
            }
            let t = ProgressionSchedule.build(voiced, chordBars: p.chordBars, barsPerChord: p.barsPerChord, beatsPerBar: p.beatsPerBar,
                                              bpm: p.bpm, rhythm: p.rhythm, countInBars: p.countInBars)
            return TimelineDTO(events: t.events.map { e in
                                   EventDTO(time: e.time, notes: zip(e.notes, e.offsets).map { EventNoteDTO(course: $0.course, cents: $0.pitch.cents, offset: $1) },
                                            velocity: e.velocity, duration: e.duration)
                               },
                               chordStarts: t.chordStarts, countIn: t.countIn, cycle: t.cycle)
        }
    }
}

/// The last voiced progression and the alternatives shown per chord, for `progression.schedule`.
enum ProgressionCache {
    nonisolated(unsafe) static var voiced: [VoicedChord] = []
    nonisolated(unsafe) static var alternatives: [Int: [ChordVoicing]] = [:]
}
