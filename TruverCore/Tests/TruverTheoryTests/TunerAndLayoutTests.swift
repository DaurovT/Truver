import Testing
@testable import TruverTheory

@Suite("Tuner targets (TU-6)")
struct TunerTargetTests {
    func note(_ s: String) -> Pitch { SpelledNote(parsing: s)!.pitch }

    @Test func autoCapturesNearestString() throws {
        let tuning = try #require(TuningTemplates.template(id: "g6-standard-e")).makeTuning()
        let played = note("A2").transposed(byCents: -12)
        guard case let .string(ref, _, deviation) = TunerTargeting.resolve(played, tuning: tuning, mode: .auto) else {
            Issue.record("expected a string"); return
        }
        #expect(ref == StringRef(course: 1))
        #expect(abs(deviation + 12) < 1e-9)
    }

    @Test("Re-tuning E2 → Drop D: chromatic note plus a hint for D2")
    func retuneHint() throws {
        let tuning = try #require(TuningTemplates.template(id: "g6-drop-d")).makeTuning()
        guard case let .chromatic(nearest, _, hint) = TunerTargeting.resolve(note("E2"), tuning: tuning, mode: .auto) else {
            Issue.record("expected chromatic"); return
        }
        #expect(nearest == note("E2"))
        #expect(hint?.string == StringRef(course: 0))
        #expect(abs((hint?.deviationCents ?? 0) - 200) < 1e-9)
    }

    @Test func manualShowsAnyDeviation() throws {
        let tuning = try #require(TuningTemplates.template(id: "g6-standard-e")).makeTuning()
        let target = TunerTargeting.resolve(note("C2"), tuning: tuning, mode: .manual(course: 0, string: 0))
        #expect(abs(target.deviationCents + 400) < 1e-9)
    }

    @Test func pairedCourseStringsAreSeparateTargets() throws {
        let six = try #require(TuningTemplates.template(id: "g6-standard-e")).makeInstrument()
        let (twelve, _) = InstrumentEditing.changingPairing(of: six, course: 0, to: .octave)
        let target = TunerTargeting.resolve(note("E3").transposed(byCents: 5), tuning: twelve.currentTuning!, mode: .auto)
        guard case let .string(ref, _, _) = target else { Issue.record("expected a string"); return }
        #expect(ref == StringRef(course: 0, string: 1))
    }
}

@Suite("Scale positions (FB-4, FB-5)")
struct LayoutTests {
    func fretboard(_ id: String) -> Fretboard {
        Fretboard(instrument: TuningTemplates.template(id: id)!.makeInstrument())!
    }

    func fretsByString(_ position: ScalePosition) -> [[Int]] {
        let courses = Set(position.notes.map(\.course)).sorted()
        return courses.map { c in position.notes.filter { $0.course == c }.map(\.fret) }
    }

    @Test func notesPerStringByScaleSize() {
        #expect(PositionLayout.notesPerString(scaleSize: 7) == [3])
        #expect(PositionLayout.notesPerString(scaleSize: 5) == [2])
        #expect(PositionLayout.notesPerString(scaleSize: 6) == [2, 3])
        #expect(PositionLayout.notesPerString(scaleSize: 8, options: LayoutOptions(eightNotePattern: .fourFour)) == [4])
    }

    @Test("G major 3nps in E standard: the classic shape from fret 3")
    func classicThreeNotesPerString() throws {
        let positions = PositionLayout.positions(.threeNotesPerString, scale: ScaleLibrary.major,
                                                 tonic: NoteName(.g), on: fretboard("g6-standard-e"))
        #expect(Set(positions.map(\.startDegree)).count == 7 && positions.count >= 7)
        let fromG = try #require(positions.first { $0.startDegree == 0 })
        #expect(fretsByString(fromG) == [[3, 5, 7], [3, 5, 7], [4, 5, 7], [4, 5, 7], [5, 7, 8], [5, 7, 8]])
        #expect(!fromG.isTruncated)
    }

    @Test("3nps works for any number of strings", arguments: ["g7-standard-b", "g8-drop-e", "g9-standard-cs", "g9-high-a"])
    func extendedRange(id: String) {
        let board = fretboard(id)
        let positions = PositionLayout.positions(.threeNotesPerString, scale: ScaleLibrary.naturalMinor,
                                                 tonic: NoteName(.e), on: board)
        #expect(Set(positions.map(\.startDegree)).count == 7 && positions.count >= 7)
        for position in positions where !position.isTruncated {  // shapes cut at fret 24 are partial by design
            #expect(position.notes.count == board.courseCount * 3, "\(id) position \(position.number)")
            let pitches = position.notes.map(\.pitch.cents)
            #expect(pitches == pitches.sorted() && Set(pitches).count == pitches.count)
        }
        #expect(positions.map(\.fretRange.lowerBound) == positions.map(\.fretRange.lowerBound).sorted())
    }

    @Test("A minor pentatonic boxes in E standard: five boxes, box at fret 5 is the classic one")
    func pentatonicBoxes() throws {
        let minorPent = try #require(ScaleLibrary.scale(id: "minor-pentatonic"))
        let boxes = PositionLayout.positions(.boxes, scale: minorPent, tonic: NoteName(.a), on: fretboard("g6-standard-e"))
        #expect(Set(boxes.map(\.startDegree)).count == 5 && boxes.count >= 5)
        let box1 = try #require(boxes.first { $0.startDegree == 0 })
        #expect(fretsByString(box1) == [[5, 8], [5, 7], [5, 7], [5, 7], [5, 8], [5, 8]])
        #expect(box1.fingers == [1, 4, 1, 3, 1, 3, 1, 3, 1, 4, 1, 4])
        for box in boxes where !box.isTruncated {  // boxes cut at fret 24 are partial by design
            #expect(box.notes.count == 12, "box \(box.number): \(fretsByString(box))")
            #expect(!box.isTruncated)
        }
    }

    @Test("Heptatonic boxes: 2–3 notes per string, every scale pitch once", arguments: ["g6-standard-e", "g7-standard-b", "g8-standard-fs"])
    func majorBoxes(id: String) {
        let board = fretboard(id)
        let boxes = PositionLayout.positions(.boxes, scale: ScaleLibrary.major, tonic: NoteName(.g), on: board)
        #expect(!boxes.isEmpty)
        for box in boxes {
            let pitches = box.notes.map(\.pitch.cents)
            #expect(pitches == pitches.sorted() && Set(pitches).count == pitches.count)
            #expect(box.fretRange.upperBound - box.fretRange.lowerBound <= 5, "\(id) box \(box.number)")
        }
    }

    @Test("Drop tunings: boxes cover the fifth between the two lowest strings without dropping notes",
          arguments: ["g6-drop-d", "g7-drop-a", "g8-drop-e", "g9-drop-b"])
    func dropBoxes(id: String) {
        let boxes = PositionLayout.positions(.boxes, scale: ScaleLibrary.major, tonic: NoteName(.g), on: fretboard(id))
        #expect(boxes.count >= 5)
        // Boxes cut at fret 24 at the top of the neck are partial by design.
        #expect(boxes.filter { $0.fretRange.upperBound < 24 }.allSatisfy { !$0.isTruncated }, "\(id)")
    }

    @Test("Open strings can be disabled")
    func noOpenStrings() {
        let positions = PositionLayout.positions(.threeNotesPerString, scale: ScaleLibrary.major, tonic: NoteName(.g),
                                                 on: fretboard("g6-standard-e"), options: LayoutOptions(allowOpenStrings: false))
        #expect(positions.allSatisfy { $0.notes.allSatisfy { $0.fret > 0 } })
        #expect(Set(positions.map(\.startDegree)).count == 7 && positions.count >= 7)
    }

    @Test("Re-entrant ukulele: layout follows pitch, notes keep physical courses")
    func ukulele() {
        let board = fretboard("ukulele-standard")
        #expect(board.coursesByPitch == [1, 2, 0, 3])
        let positions = PositionLayout.positions(.threeNotesPerString, scale: ScaleLibrary.major, tonic: NoteName(.c), on: board)
        #expect(!positions.isEmpty)
        for position in positions {
            let pitches = position.notes.map(\.pitch.cents)
            #expect(pitches == pitches.sorted())
        }
    }

    @Test("Whole neck and chord tones")
    func wholeNeck() {
        let board = fretboard("g6-standard-e")
        let notes = board.notes(of: ScaleLibrary.major, tonic: NoteName(.c))
        // 25 frets (0…24) per string: two octaves give 14 notes, fret 24 repeats the open note (in C major here).
        #expect(notes.count == 6 * 15)
        #expect(notes.allSatisfy { ScaleLibrary.major.degreeIndex(of: $0.pitch, tonic: NoteName(.c)) == $0.degreeIndex })
        let chordTones = board.notes(of: ChordLibrary.major, root: NoteName(.c))
        #expect(chordTones.allSatisfy { [0, 4, 7].contains(mod($0.pitch.nearestMIDI - 60, 12)) })
    }

    @Test func playbackOrders() {
        #expect(PlaybackPattern.thirds.order(noteCount: 5) == [0, 2, 1, 3, 2, 4])
        #expect(PlaybackPattern.sequence(groupSize: 3).order(noteCount: 5) == [0, 1, 2, 1, 2, 3, 2, 3, 4])
        #expect(PlaybackPattern.down.order(noteCount: 3) == [2, 1, 0])
        #expect(PlaybackPattern.thirds.order(noteCount: 4, descending: true) == [3, 1, 2, 0])
    }
}

@Suite("Positions up the whole neck")
struct PositionsUpTheNeckTests {
    @Test("Guitars of 6–9 strings and basses: positions end at fret 24")
    func continuesUp() {
        for (id, frets) in [("g8-drop-e", 24), ("g6-standard-e", 24), ("g7-standard-b", 24), ("b4-standard", 24)] {
            let template = TuningTemplates.template(id: id)!
            let instrument = template.makeInstrument()
            #expect(instrument.fretCount == frets)
            let board = Fretboard(instrument: instrument)!
            for kind in [LayoutKind.threeNotesPerString, .boxes] {
                let positions = PositionLayout.positions(kind, scale: ScaleLibrary.major, tonic: NoteName(.g), on: board)
                let top = positions.map(\.fretRange.upperBound).max() ?? 0
                #expect(positions.count > 7, "\(id) \(kind): \(positions.count)")
                #expect(top == frets, "\(id) \(kind): top fret \(top)")
                #expect(positions.map(\.number) == Array(1...positions.count))
            }
        }
    }
}

@Suite("Playback cycles")
struct PlaybackCycleTests {
    @Test("Up-down plays the top once; in a loop the bottom is not doubled either")
    func upDown() {
        #expect(PlaybackPattern.up.cycle(noteCount: 4, direction: .upDown, loop: false) == [0, 1, 2, 3, 2, 1, 0])
        #expect(PlaybackPattern.up.cycle(noteCount: 4, direction: .upDown, loop: true) == [0, 1, 2, 3, 2, 1])
        #expect(PlaybackPattern.up.cycle(noteCount: 4, direction: .down, loop: true) == [3, 2, 1, 0])
        #expect(PlaybackPattern.thirds.cycle(noteCount: 4, direction: .upDown, loop: false) == [0, 2, 1, 3, 3, 1, 2, 0])
    }
}
