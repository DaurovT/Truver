import Testing
@testable import TruverTheory

@Suite("Chords and key chords")
struct ChordTests {
    @Test func spelling() {
        #expect(ChordLibrary.diminished7.spell(root: NoteName(.b)).map(\.description) == ["B", "D", "F", "A♭"])
        #expect(ChordLibrary.dominant7.spell(root: NoteName(.e, -1)).map(\.description) == ["E♭", "G", "B♭", "D♭"])
        #expect(ChordLibrary.major7.optionalDegrees == [DegreeLabel(5)])
        #expect(ChordLibrary.halfDiminished7.optionalDegrees.isEmpty)
    }

    @Test("TH-4: triads and sevenths of C major")
    func cMajor() throws {
        let triads = try #require(KeyChords.triads(ScaleLibrary.major, tonic: NoteName(.c)))
        #expect(triads.map { $0.name() } == ["C", "Dm", "Em", "F", "G", "Am", "Bdim"])
        #expect(triads.map(\.romanNumeral) == ["I", "ii", "iii", "IV", "V", "vi", "vii°"])
        let sevenths = try #require(KeyChords.sevenths(ScaleLibrary.major, tonic: NoteName(.c)))
        #expect(sevenths.map { $0.name() } == ["Cmaj7", "Dm7", "Em7", "Fmaj7", "G7", "Am7", "Bm7♭5"])
        #expect(sevenths.map(\.romanNumeral) == ["Imaj7", "ii7", "iii7", "IVmaj7", "V7", "vi7", "viiø7"])
    }

    @Test func minorRomanNumeralsCarryAccidentals() throws {
        let triads = try #require(KeyChords.triads(ScaleLibrary.naturalMinor, tonic: NoteName(.a)))
        #expect(triads.map(\.romanNumeral) == ["i", "ii°", "♭III", "iv", "v", "♭VI", "♭VII"])
    }

    @Test func harmonicMinorHasAugmentedAndUnknownChords() throws {
        let triads = try #require(KeyChords.triads(ScaleLibrary.harmonicMinor, tonic: NoteName(.a)))
        #expect(triads[2].name() == "Caug")
        #expect(triads[2].romanNumeral == "♭III+")
        let sevenths = try #require(KeyChords.sevenths(ScaleLibrary.harmonicMinor, tonic: NoteName(.a)))
        #expect(sevenths[0].name() == "Am(maj7)")
        #expect(sevenths[6].name() == "G♯dim7")
        #expect(sevenths[2].chord == nil) // Cmaj7♯5 is outside TH-3a
    }

    @Test func nonHeptatonicHasNoKeyChords() throws {
        #expect(KeyChords.triads(try #require(ScaleLibrary.scale(id: "minor-pentatonic")), tonic: NoteName(.a)) == nil)
    }

    @Test("TH-7: progression transposition keeps letters")
    func progression() {
        let progression = [
            Transposition.ChordSymbol(root: NoteName(.c), chord: ChordLibrary.major),
            Transposition.ChordSymbol(root: NoteName(.a), chord: ChordLibrary.minor),
            Transposition.ChordSymbol(root: NoteName(.f), chord: ChordLibrary.major),
            Transposition.ChordSymbol(root: NoteName(.g), chord: ChordLibrary.dominant7),
        ]
        let moved = Transposition.transpose(progression, from: NoteName(.c), to: NoteName(.e, -1))
        #expect(moved.map { $0.chord.name(root: $0.root) } == ["E♭", "Cm", "A♭", "B♭7"])
    }
}
