import Testing
@testable import TruverTheory

@Suite("Chord tools (FB-9, FB-10, FB-21)")
struct ChordToolsTests {
    private func board(_ id: String) -> Fretboard {
        Fretboard(instrument: TuningTemplates.template(id: id)!.makeInstrument())!
    }

    @Test("Extended library parses and spells (C13♯11, G7♯9)")
    func library() {
        let c = ChordLibrary.anyChord(id: "13#11")!
        #expect(c.spell(root: NoteName(.c)).map(\.description) == ["C", "E", "G", "B♭", "D", "F♯", "A"])
        #expect(ChordLibrary.anyChord(id: "7#9")!.spell(root: NoteName(.g)).map(\.description) == ["G", "B", "D", "F", "A♯"])
    }

    @Test("Omitting a degree removes it from the tones and the required set")
    func omitting() {
        let c = ChordLibrary.anyChord(id: "13#11")!.omitting([DegreeLabel(11, 1)])
        #expect(c.spell(root: NoteName(.c)).map(\.description) == ["C", "E", "G", "B♭", "D", "A"])
        #expect(!c.requiredDegrees.contains(DegreeLabel(11, 1)))
        #expect(c.id != "13#11")
    }

    @Test("TH-3b: a chord that does not fit gets a hint which degree to drop, and dropping it fits")
    func omissionHint() {
        let b = board("g6-standard-e")
        let c13 = ChordLibrary.anyChord(id: "13#11")!
        // Places on the 6th–4th strings where X13♯11 from that note does not fit (FB-21 sheet).
        var hinted = 0
        for course in 0..<3 {
            for fret in 1...12 {
                let anchor = (course: course, fret: fret)
                guard let pc = b.pitch(course: course, fret: fret)?.pitchClass else { continue }
                let root = NoteName.simpleSpelling(ofPitchClass: pc, preferFlats: false)
                guard ChordVoicings.voicings(chord: c13, root: root, on: b, anchor: anchor, limit: 1).isEmpty else { continue }
                guard let hint = ChordVoicings.omissionHint(chord: c13, root: root, on: b, anchor: anchor) else { continue }
                #expect([9, 11, 13].contains(hint.number))
                #expect(!ChordVoicings.voicings(chord: c13.omitting([hint]), root: root, on: b, anchor: anchor, limit: 1).isEmpty)
                hinted += 1
            }
        }
        #expect(hinted > 0)
        // A chord that fits needs no hint.
        #expect(ChordVoicings.omissionHint(chord: ChordLibrary.major, root: NoteName(.c), on: b) == nil)
    }

    @Test("Am7 in E standard: the classic shapes, all within 4 fingers")
    func am7() {
        let v = ChordVoicings.voicings(chord: ChordLibrary.minor7, root: NoteName(.a), on: board("g6-standard-e"))
        #expect(!v.isEmpty)
        #expect(v.allSatisfy { $0.fingers <= 4 && $0.span <= 4 })
        #expect(v.allSatisfy { $0.bass.pitch.pitchClass == 9 })
        let shapes = Set(v.map { $0.frets.map { $0.map(String.init) ?? "x" }.joined() })
        #expect(shapes.contains("x02010"))        // open Am7
        #expect(shapes.contains("575585"))        // E-shape barre at 5
    }

    @Test("8-string: voicings exist with the bass on the 6th string and on the 8th")
    func eightString() {
        let b = board("g8-drop-e")
        let v = ChordVoicings.voicings(chord: ChordLibrary.minor7, root: NoteName(.a), on: b, limit: 60)
        #expect(v.contains { $0.bass.course == 2 })   // A on the 6th string (index 2 of 8)
        let anchored = ChordVoicings.voicings(chord: ChordLibrary.minor, root: NoteName(.a), on: b, anchor: (2, 5))
        #expect(!anchored.isEmpty && anchored.allSatisfy { $0.bass.course == 2 && $0.bass.fret == 5 })
    }

    @Test("Recognition: A C E G with A in the bass is Am7, also C6/A")
    func recognise() {
        let names = ChordRecognizer.identify(pitchClasses: [9, 0, 4, 7], bass: 9).map { $0.name() }
        #expect(names.first == "Am7")
        #expect(names.contains("C6/A"))
        let partial = ChordRecognizer.identify(pitchClasses: [7, 11, 5], bass: 7).map { $0.name() }
        #expect(partial.first == "G7 без D" || partial.first?.hasPrefix("G7") == true)
    }

    @Test("Scales containing F♯ A D G: D major first with D in the bass")
    func scales() {
        let found = ScaleFinder.scales(containing: [6, 9, 2, 7], preferredTonic: 2)
        #expect(found.first?.tonic.pitchClass == 2)
        #expect(found.contains { $0.scale.id == "major" && $0.tonic.pitchClass == 2 })
    }
}

@Suite("Scale path (FB-20)")
struct ScalePathTests {
    @Test("E standard, G major from G on the 6th string, 3rd fret")
    func paths() {
        let b = Fretboard(instrument: TuningTemplates.template(id: "g6-standard-e")!.makeInstrument())!
        let three = ScalePath.build(.threePerString, scale: ScaleLibrary.major, tonic: NoteName(.g), on: b, start: (0, 3))
        #expect(three.count == 18)
        #expect(three.prefix(3).map(\.fret) == [3, 5, 7])
        let four = ScalePath.build(.fourDiagonal, scale: ScaleLibrary.major, tonic: NoteName(.g), on: b, start: (0, 3))
        #expect(four.prefix(5).map(\.fret) == [3, 5, 7, 8, 5])     // G A B C | D on the A string
        #expect(four.last!.course == 5)
        #expect(zip(four, four.dropFirst()).allSatisfy { $0.pitch.cents < $1.pitch.cents })
        let one = ScalePath.build(.oneString, scale: ScaleLibrary.major, tonic: NoteName(.g), on: b, start: (4, 0))
        #expect(one.allSatisfy { $0.course == 4 } && one.last!.fret <= 24 && one.count > 10)
    }
}

@Suite("Scale path in drop tunings")
struct ScalePathDropTests {
    @Test("8-string Drop E: 3 per string from the open low E crosses every string")
    func dropE() {
        let b = Fretboard(instrument: TuningTemplates.template(id: "g8-drop-e")!.makeInstrument())!
        let path = ScalePath.build(.threePerString, scale: ScaleLibrary.major, tonic: NoteName(.e), on: b, start: (0, 0))
        #expect(path.last?.course == 7)
        #expect(path.count >= 24)
        #expect(zip(path, path.dropFirst()).allSatisfy { $0.pitch.cents < $1.pitch.cents })
    }
}

@Suite("FB-10 readable search results")
struct SearchNamesTests {
    @Test("No double accidentals in names and the bass is the played note")
    func spelling() {
        // G G♯ C♯ F with G in the bass: the UX check got «C♯7♯11/F𝄪 без B».
        let m = ChordRecognizer.identify(pitchClasses: [7, 8, 1, 5], bass: 7)
        #expect(!m.isEmpty)
        for x in m {
            #expect(!x.name().contains("𝄪") && !x.name().contains("𝄫"), "\(x.name())")
            if let b = x.bass { #expect(b.pitchClass == 7 && abs(b.accidental) <= 1) }
        }
    }

    @Test("A pressed C is never called B♯ in the bass")
    func awkwardBass() {
        let m = ChordRecognizer.identify(pitchClasses: [0, 5, 6, 8], bass: 0)
        #expect(!m.isEmpty)
        for x in m {
            #expect(!x.name().contains("B♯") && !x.name().contains("E♯"), "\(x.name())")
            if let b = x.bass { #expect(b == NoteName(.c)) }
        }
    }

    @Test("Nearest chord when nothing fits all the notes")
    func nearest() {
        let cluster: Set<Int> = [0, 1, 2, 3]
        #expect(ChordRecognizer.identify(pitchClasses: cluster, bass: 0).isEmpty)
        let n = ChordRecognizer.nearest(pitchClasses: cluster, bass: 0)
        #expect(n?.matched == 3)
    }
}

@Suite("FB-25 position from a note")
struct PositionFromNoteTests {
    private func board(_ id: String, capo: Int = 0) -> Fretboard {
        var i = TuningTemplates.template(id: id)!.makeInstrument()
        i.capo = capo
        return Fretboard(instrument: i)!
    }

    @Test("Starts on the pressed note, which is the lowest; every note is in the scale; ascending", arguments: ["g6-standard-e", "g8-drop-e", "b4-standard"])
    func threePerString(id: String) throws {
        let b = board(id)
        let scale = ScaleLibrary.scale(id: "aeolian")!
        let course = 1, fret = 5
        let pitch = try #require(b.pitch(course: course, fret: fret))
        let tonic = NoteName.simpleSpelling(ofPitchClass: pitch.pitchClass, preferFlats: false)
        for kind in [LayoutKind.threeNotesPerString, .boxes] {
            let p = try #require(PositionLayout.position(from: (course, fret), kind: kind, scale: scale, tonic: tonic, on: b))
            #expect(p.notes.first?.course == course && p.notes.first?.fret == fret)
            #expect(p.notes.allSatisfy { $0.pitch >= pitch })
            #expect(zip(p.notes, p.notes.dropFirst()).allSatisfy { $0.pitch < $1.pitch })
            #expect(p.notes.allSatisfy { scale.degreeIndex(of: $0.pitch, tonic: tonic) != nil })
            #expect(p.notes.count >= 4)
        }
    }

    @Test("A note outside the scale has no position; a capo keeps every note at or above it")
    func outsideAndCapo() throws {
        let b = board("g6-standard-e", capo: 3)
        let g = NoteName(.g)
        // Low E string, fret 4 = G♯: not in G major.
        #expect(PositionLayout.position(from: (0, 4), kind: .threeNotesPerString, scale: ScaleLibrary.major, tonic: g, on: b) == nil)
        let p = try #require(PositionLayout.position(from: (0, 3), kind: .threeNotesPerString, scale: ScaleLibrary.major, tonic: g, on: b))
        #expect(p.notes.allSatisfy { $0.fret >= 3 })
        #expect(PositionLayout.positions(.threeNotesPerString, scale: ScaleLibrary.major, tonic: g, on: b).allSatisfy { $0.fretRange.lowerBound >= 3 })
    }
}

@Suite("FB-25 mode from a note")
struct ModeFromNoteTests {
    @Test("G major from B is B Phrygian; A minor from C is C major; a note outside the scale gives nil")
    func modes() {
        let major = ScaleLibrary.scale(id: "major")!
        #expect(ScaleLibrary.mode(of: major, tonic: NoteName(.g), startingOn: NoteName(.b).pitchClass)?.id == "phrygian")
        #expect(ScaleLibrary.mode(of: major, tonic: NoteName(.g), startingOn: NoteName(.a).pitchClass)?.id == "dorian")
        let aeolian = ScaleLibrary.scale(id: "aeolian")!
        #expect(ScaleLibrary.mode(of: aeolian, tonic: NoteName(.a), startingOn: NoteName(.c).pitchClass)?.id == "major")
        #expect(ScaleLibrary.mode(of: major, tonic: NoteName(.g), startingOn: NoteName(.f).pitchClass) == nil)
        let hm = ScaleLibrary.scale(id: "harmonic-minor")!
        #expect(ScaleLibrary.mode(of: hm, tonic: NoteName(.a), startingOn: NoteName(.e).pitchClass)?.id == "phrygian-dominant")
    }
}

@Suite("5.1.4 long note names")
struct NotationLayoutTests {
    @Test("«соль♯» shortens to «сол♯» only in Russian solfège; dial sizes 96 / 72 / 60")
    func short() {
        let sol = NoteFormatter(notation: .solfege)
        #expect(sol.short(NoteName(.g, 1)) == "сол♯")
        #expect(sol.short(NoteName(.a)) == "ля")
        #expect(NoteFormatter().short(NoteName(.g, 1)) == "G♯")
        #expect(NoteFormatter.dialSize(for: "A") == 96)
        #expect(NoteFormatter.dialSize(for: "C♯") == 96)
        #expect(NoteFormatter.dialSize(for: "ля♭") == 72)
        #expect(NoteFormatter.dialSize(for: "соль♯") == 60)
        #expect(NoteFormatter(notation: .german).string(NoteName(.b, -1)) == "B")
        #expect(NoteFormatter(notation: .german).string(NoteName(.b)) == "H")
    }
}
