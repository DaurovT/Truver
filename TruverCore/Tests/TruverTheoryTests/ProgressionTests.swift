import Testing
@testable import TruverTheory

@Suite("Progressions (FB-11, FB-22, FB-24, TH-7)")
struct ProgressionTests {
    private func board(_ id: String) -> Fretboard {
        Fretboard(instrument: TuningTemplates.template(id: id)!.makeInstrument())!
    }
    private func names(_ p: Progression) -> [String] {
        p.symbols.map { $0.root.description + $0.chord.symbol }
    }

    @Test("Roman numerals parse into roots and types, spelled by the degree's letter")
    func numerals() {
        let c = NoteName(.c)
        #expect(ProgressionChord(numeral: "ii7")!.root(in: c) == NoteName(.d))
        #expect(ProgressionChord(numeral: "ii7")!.chordId == "m7")
        #expect(ProgressionChord(numeral: "V7")!.chordId == "7")
        #expect(ProgressionChord(numeral: "iiø7")!.chordId == "m7b5")
        #expect(ProgressionChord(numeral: "vii°")!.chordId == "dim")
        #expect(ProgressionChord(numeral: "bVII")!.root(in: NoteName(.e)) == NoteName(.d))
        #expect(ProgressionChord(numeral: "♭VI")!.root(in: NoteName(.e)) == NoteName(.c))      // not B♯
        #expect(ProgressionChord(numeral: "♭II")!.root(in: NoteName(.e)) == NoteName(.f))
        #expect(ProgressionChord(numeral: "IV")!.root(in: NoteName(.f)) == NoteName(.b, -1))   // B♭, not A♯
        #expect(ProgressionChord(numeral: "Imaj7") != nil && ProgressionChord(numeral: "I5")?.chordId == "5")
        #expect(ProgressionChord(numeral: "X") == nil)
        #expect(ProgressionChord(numeral: "Iv") == nil)
        #expect(ProgressionChord(numeral: "iiø7")!.numeral == "iiø7")
        #expect(ProgressionChord(numeral: "♭VII")!.numeral == "♭VII")
    }

    @Test("Any chord in a key keeps its root, in every key")
    func anyRoot() {
        for keyPC in 0..<12 {
            let key = NoteName.simpleSpelling(ofPitchClass: keyPC, preferFlats: true)
            for rootPC in 0..<12 {
                let root = NoteName.simpleSpelling(ofPitchClass: rootPC, preferFlats: rootPC % 2 == 0)
                let c = ProgressionChord(root: root, in: key, chordId: "maj9")
                #expect(c.root(in: key) == root)
            }
        }
        #expect(ProgressionChord(root: NoteName(.e, -1), in: NoteName(.c), chordId: "maj").numeral == "♭III")
    }

    @Test("Library: every template parses; pop in G = G D Em C; blues has 12 bars")
    func library() {
        let all = ProgressionLibrary.all(key: NoteName(.g))
        #expect(all.count >= 10)
        let pop = all.first { $0.id == "pop" }!
        #expect(names(pop) == ["G", "D", "Em", "C"])
        #expect(all.first { $0.id == "blues" }!.totalBars == 12)
        let andalusian = ProgressionLibrary.all(key: NoteName(.a)).first { $0.id == "andalusian" }!
        #expect(names(andalusian) == ["Am", "G", "F", "E"])
    }

    @Test("TH-7: ii–V–I from C to E♭ and by semitones with a simple key spelling")
    func transpose() {
        let p = ProgressionLibrary.all(key: NoteName(.c)).first { $0.id == "jazz-251" }!
        #expect(names(p.transposed(to: NoteName(.e, -1))) == ["Fm7", "B♭7", "E♭maj7", "E♭maj7"])
        #expect(p.transposed(bySemitones: 3).key == NoteName(.e, -1))       // E♭, not D♯
        #expect(p.transposed(bySemitones: 6).key.pitchClass == 6)
        #expect(p.transposed(bySemitones: -1).key == NoteName(.b))          // B, not C♭
        #expect(p.transposed(bySemitones: 1).key == NoteName(.d, -1))       // D♭, not C♯
    }

    @Test("Voice leading: every chord voiced, the hand moves less than with each chord's own best shape")
    func voiceLeading() {
        let b = board("g6-standard-e")
        let p = ProgressionLibrary.all(key: NoteName(.g)).first { $0.id == "pop" }!
        let voiced = ProgressionVoicer.voice(p.symbols, on: b)
        #expect(voiced.allSatisfy { $0.voicing != nil })
        let led = zip(voiced, voiced.dropFirst()).reduce(0.0) { $0 + ProgressionVoicer.movement($1.0.voicing!, $1.1.voicing!) }
        let independent = p.symbols.map { ChordVoicings.voicings(chord: $0.chord, root: $0.root, on: b, limit: 1)[0] }
        let naive = zip(independent, independent.dropFirst()).reduce(0.0) { $0 + ProgressionVoicer.movement($1.0, $1.1) }
        #expect(led <= naive + 1e-9)
        // Each chosen voicing really is that chord.
        for v in voiced {
            let pcs = Set(v.chord.spell(root: v.root).map(\.pitchClass))
            #expect(v.voicing!.notes.allSatisfy { pcs.contains($0.pitch.pitchClass) })
        }
    }

    @Test("FB-22: from a place — the first chord starts there, the rest stay in the window or are marked")
    func fromPlace() {
        let b = board("g7-standard-b")
        // A on the 6th string (course 1 on a 7-string), 5th fret.
        let anchor = (course: 1, fret: 5)
        let window = ProgressionVoicer.window(around: 5, fretCount: b.instrument.fretCount)
        #expect(window == 4...8)
        let p = ProgressionLibrary.all(key: NoteName(.a)).first { $0.id == "epic-minor" }!
        let voiced = ProgressionVoicer.voice(p.symbols, on: b, window: window, anchor: anchor)
        #expect(voiced[0].voicing?.bass.course == 1 && voiced[0].voicing?.bass.fret == 5)
        for v in voiced {
            guard let voicing = v.voicing else { Issue.record("no voicing for \(v.root)"); continue }
            #expect(v.outOfWindow == (ProgressionVoicer.distance(voicing, to: window) > 0))
        }
        #expect(voiced.filter { !$0.outOfWindow }.count >= 3)
    }

    @Test("Extended-range guitar and bass: voicing a progression never crashes; power chords on an 8-string")
    func extendedRange() {
        for id in ["g8-drop-e", "g9-standard-c#", "b4-standard"] {
            guard let template = TuningTemplates.template(id: id) else { continue }
            let b = Fretboard(instrument: template.makeInstrument())!
            let p = ProgressionLibrary.all(key: NoteName(.e)).first { $0.id == "power" }!
            let voiced = ProgressionVoicer.voice(p.symbols, on: b, loop: true)
            #expect(voiced.count == 4)
            if id == "g8-drop-e" { #expect(voiced.allSatisfy { $0.voicing != nil }) }
        }
    }

    @Test("FB-24 schedule: count-in, a stroke per bar / per beat / down-up eighths, 12 ms per string")
    func schedule() {
        let b = board("g6-standard-e")
        let p = ProgressionLibrary.all(key: NoteName(.c)).first { $0.id == "three" }!
        let voiced = ProgressionVoicer.voice(p.symbols, on: b)
        let bars = p.chords.map(\.bars)
        let perBar = ProgressionSchedule.build(voiced, chordBars: bars, beatsPerBar: 4, bpm: 120, rhythm: .perBar)
        #expect(perBar.countIn == 2.0)
        #expect(perBar.events.count == 4)
        #expect(perBar.events.map(\.time) == [2, 4, 6, 8])
        #expect(perBar.cycle == 8)
        let first = perBar.events[0]
        #expect(first.isDown && first.offsets[1] == 0.012)
        #expect(first.notes.map(\.course) == first.notes.map(\.course).sorted())
        #expect(abs(first.duration - 2) < 1e-9)
        #expect(perBar.chordIndex(at: 1, looping: true) == nil)
        #expect(perBar.chordIndex(at: 4.5, looping: true) == 1)
        #expect(perBar.chordIndex(at: 2 + 8 + 6.1, looping: true) == 3)
        #expect(perBar.chordIndex(at: 2 + 8 + 0.5, looping: false) == nil)

        let perBeat = ProgressionSchedule.build(voiced, chordBars: bars, barsPerChord: 2, beatsPerBar: 4, bpm: 120, rhythm: .perBeat)
        #expect(perBeat.events.count == 4 * 2 * 4)
        #expect(perBeat.chordStarts == [2, 6, 10, 14])

        let eighths = ProgressionSchedule.build(voiced, chordBars: bars, beatsPerBar: 4, bpm: 120, rhythm: .downUpEighths, countInBars: 0)
        #expect(eighths.events.count == 4 * 8)
        let up = eighths.events[1]
        #expect(!up.isDown && up.time == 0.25 && up.notes.count <= 4 && up.velocity < eighths.events[0].velocity)
        #expect(up.notes.map(\.course) == up.notes.map(\.course).sorted(by: >))
    }
}
