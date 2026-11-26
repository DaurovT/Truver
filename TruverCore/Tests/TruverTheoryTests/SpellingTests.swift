import Testing
@testable import TruverTheory

@Suite("Spelling rules 5.2.1")
struct SpellingTests {
    func names(_ scale: Scale, _ tonic: String) -> String {
        ScaleSpeller.spell(scale, tonic: NoteName(parsing: tonic)!).map(\.description).joined(separator: " ")
    }

    @Test func libraryHasAboutFortyScales() {
        #expect((38...45).contains(ScaleLibrary.all.count))
        #expect(Set(ScaleLibrary.all.map(\.id)).count == ScaleLibrary.all.count)
    }

    @Test("Rule 1: one letter per degree")
    func heptatonic() {
        #expect(names(ScaleLibrary.major, "D") == "D E F♯ G A B C♯")
        #expect(names(ScaleLibrary.naturalMinor, "E♭") == "E♭ F G♭ A♭ B♭ C♭ D♭")
        #expect(names(ScaleLibrary.lydian, "F") == "F G A B C D E")
    }

    @Test("Modes are parent + shift, labels recomputed")
    func modes() throws {
        let ultra = try #require(ScaleLibrary.scale(id: "ultralocrian"))
        #expect(ultra.mode == ModeReference(parentId: "harmonic-minor", shift: 6))
        #expect(ultra.degrees.map(\.label.description) == ["1", "♭2", "♭3", "♭4", "♭5", "♭6", "𝄫7"])
        let altered = try #require(ScaleLibrary.scale(id: "altered"))
        #expect(names(altered, "G") == "G A♭ B♭ C♭ D♭ E♭ F")
    }

    @Test("Rule 2: pentatonic and blues from the parent scale")
    func pentatonicAndBlues() throws {
        let blues = try #require(ScaleLibrary.scale(id: "blues"))
        #expect(names(blues, "A") == "A C D E♭ E G")
        let minorPent = try #require(ScaleLibrary.scale(id: "minor-pentatonic"))
        #expect(names(minorPent, "F♯") == "F♯ A B C♯ E")
    }

    @Test("Rule 3: whole-tone and augmented by tonic accidental")
    func wholeTone() throws {
        let wt = try #require(ScaleLibrary.scale(id: "whole-tone"))
        #expect(names(wt, "C") == "C D E F♯ G♯ A♯")
        #expect(names(wt, "D♭") == "D♭ E♭ F G A B")
        #expect(names(wt, "F♯") == "F♯ G♯ A♯ C D E")
    }

    @Test("Rule 4: 8-note scales repeat exactly one letter")
    func eightNotes() throws {
        for id in ["diminished-whole-half", "diminished-half-whole", "bebop-dominant", "bebop-major", "bebop-dorian"] {
            let scale = try #require(ScaleLibrary.scale(id: id))
            for pc in 0..<12 {
                let spelled = ScaleSpeller.spell(scale, tonicPitchClass: pc).notes
                #expect(Set(spelled.map(\.letter)).count == 7, "\(id) on \(pc)")
            }
        }
        #expect(names(ScaleLibrary.scale(id: "bebop-dominant")!, "G") == "G A B C D E F F♯")
        #expect(names(ScaleLibrary.scale(id: "diminished-whole-half")!, "C") == "C D E♭ F G♭ A♭ A B")
    }

    @Test("Rule 5: chromatic sharps up, flats down")
    func chromatic() throws {
        let chromatic = try #require(ScaleLibrary.scale(id: "chromatic"))
        #expect(names(chromatic, "C") == "C C♯ D D♯ E F F♯ G G♯ A A♯ B")
        let down = ScaleSpeller.spell(chromatic, tonic: NoteName(.c), direction: .descending)
        #expect(down.map(\.description).joined(separator: " ") == "C D♭ D E♭ E F G♭ G A♭ A B♭ B")
    }

    @Test("Rule 6: fewer real accidentals wins")
    func enharmonicChoice() throws {
        #expect(ScaleSpeller.preferredTonic(pitchClass: 8, scale: ScaleLibrary.major) == NoteName(.a, -1))
        #expect(ScaleSpeller.preferredTonic(pitchClass: 8, scale: ScaleLibrary.naturalMinor) == NoteName(.g, 1))
        let hungarian = try #require(ScaleLibrary.scale(id: "hungarian-minor"))
        #expect(ScaleSpeller.preferredTonic(pitchClass: 8, scale: hungarian) == NoteName(.a, -1))
        // Tie (6 vs 6) goes to the preference.
        #expect(ScaleSpeller.preferredTonic(pitchClass: 6, scale: ScaleLibrary.major, preference: .flat) == NoteName(.g, -1))
        #expect(ScaleSpeller.preferredTonic(pitchClass: 6, scale: ScaleLibrary.major, preference: .sharp) == NoteName(.f, 1))
    }

    @Test("Rule 7: exotic heptatonic scales may need double accidentals")
    func doubleAccidentals() throws {
        let hungarian = try #require(ScaleLibrary.scale(id: "hungarian-minor"))
        #expect(names(hungarian, "G♯") == "G♯ A♯ B C𝄪 D♯ E F𝄪")
    }

    @Test("All scales in all 12 keys: right pitches, valid letters, at most double accidentals")
    func allScalesAllKeys() {
        for scale in ScaleLibrary.all {
            for pc in 0..<12 {
                let (tonic, notes) = ScaleSpeller.spell(scale, tonicPitchClass: pc)
                #expect(tonic.pitchClass == pc)
                let expected = scale.degrees.map { mod(pc + $0.semitones, 12) }
                #expect(notes.map(\.pitchClass) == expected, "\(scale.id) on \(pc)")
                #expect(notes.allSatisfy { abs($0.accidental) <= 2 }, "\(scale.id) on \(pc): \(notes)")
                if scale.count == 7 {
                    #expect(Set(notes.map(\.letter)).count == 7, "\(scale.id) on \(pc)")
                }
            }
        }
    }

    @Test("Degree roles for colours (FB-3)")
    func roles() {
        let lydian = ScaleLibrary.lydian
        #expect(lydian.role(ofDegree: 0) == .tonic)
        #expect(lydian.role(ofDegree: 3) == .characteristic)
        #expect(lydian.role(ofDegree: 2) == .chordTone)
        #expect(lydian.role(ofDegree: 1) == .other)
    }
}
