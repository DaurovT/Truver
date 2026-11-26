import Testing
@testable import TruverTheory

@Suite("Pitch and note names")
struct PitchAndNamesTests {
    @Test func a4IsZeroCents() {
        #expect(Pitch(frequency: 440).cents == 0)
        #expect(abs(Pitch(cents: 0).frequency(a4: 432) - 432) < 1e-9)
    }

    @Test("Low notes of 8–9 strings match bass notes (PRD 11)",
          arguments: [("B0", 30.868), ("C♯1", 34.648), ("F♯1", 46.249), ("E2", 82.407)])
    func lowNoteFrequencies(note: String, hz: Double) throws {
        let n = try #require(SpelledNote(parsing: note))
        #expect(abs(n.pitch.frequency() - hz) < 0.01)
    }

    @Test func scientificOctaveBelongsToLetter() throws {
        #expect(try #require(SpelledNote(parsing: "B♯3")).midi == 60)
        #expect(try #require(SpelledNote(parsing: "C♭4")).midi == 59)
        #expect(SpelledNote(NoteName(.b, 1), midi: 60).octave == 3)
        #expect(SpelledNote(NoteName(.c, -1), midi: 59).octave == 4)
    }

    @Test func parsingAccidentals() {
        #expect(NoteName(parsing: "F#") == NoteName(.f, 1))
        #expect(NoteName(parsing: "B♭") == NoteName(.b, -1))
        #expect(NoteName(parsing: "Bb") == NoteName(.b, -1))
        #expect(NoteName(parsing: "E𝄫") == NoteName(.e, -2))
        #expect(NoteName(parsing: "Cx") == NoteName(.c, 2))
        #expect(NoteName(parsing: "H") == nil)
    }

    @Test func deviationFromNearestSemitone() {
        let p = Pitch(frequency: 441)
        #expect(p.nearestMIDI == 69)
        #expect(abs(p.deviationFromNearestSemitone - 3.93) < 0.01)
    }

    @Test("Notation 5.1.4")
    func notations() {
        let intl = NoteFormatter(notation: .international)
        let german = NoteFormatter(notation: .german)
        let solfege = NoteFormatter(notation: .solfege, language: .ru)
        #expect(intl.string(NoteName(.b, -1)) == "B♭")
        #expect(german.string(NoteName(.b)) == "H")
        #expect(german.string(NoteName(.b, -1)) == "B")
        #expect(german.string(NoteName(.b, -2)) == "B♭")
        #expect(german.string(NoteName(.e, -1)) == "E♭")
        #expect(solfege.string(NoteName(.f, 1)) == "фа♯")
        #expect(solfege.string(SpelledNote(NoteName(.a), octave: 4)) == "ля4")
    }

    @Test func transposition() {
        let interval = Interval(from: NoteName(.c), to: NoteName(.e, -1))
        #expect(NoteName(.d).transposed(by: interval) == NoteName(.f))
        #expect(NoteName(.b).transposed(by: interval) == NoteName(.d))
        #expect(NoteName(.f, 1).transposed(by: interval) == NoteName(.a))
    }
}
