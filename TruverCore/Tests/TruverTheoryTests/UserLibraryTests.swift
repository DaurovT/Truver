import Foundation
import Testing
@testable import TruverTheory

@Suite("User scales and chords (TH-8)", .serialized)
struct UserLibraryTests {
    @Test("Seven notes keep one letter per degree; others get common names")
    func scaleLabels() {
        let phrygianDominant = Scale.user(id: "u1", name: "Моя", semitones: [0, 1, 4, 5, 7, 8, 10])
        #expect(phrygianDominant.degrees.map(\.label.description) == ["1", "♭2", "3", "4", "5", "♭6", "♭7"])
        let hexa = Scale.user(id: "u2", name: "Шесть", semitones: [7, 0, 3, 5, 10, 6, 3])
        #expect(hexa.semitoneSet == [0, 3, 5, 6, 7, 10])
        #expect(hexa.degrees.map(\.label.description) == ["1", "♭3", "4", "♭5", "5", "♭7"])
        // Seven notes that would need double accidentals fall back to common names.
        let cluster = Scale.user(id: "u3", name: "Кластер", semitones: [0, 1, 2, 3, 4, 5, 6])
        #expect(cluster.degrees.allSatisfy { abs($0.label.accidental) <= 1 })
        #expect(cluster.isUserDefined && cluster.category == .user)
    }

    @Test("Registered scales and chords are found by the libraries and by recognition")
    func registry() {
        let scale = Scale.user(id: "user-scale-test", name: "Тестовая", semitones: [0, 2, 3, 6, 7, 8, 11])
        let chord = Chord.user(id: "user-chord-test", name: "Мой", symbol: "maj7♯11no3",
                               labels: [DegreeLabel(5), DegreeLabel(7), DegreeLabel(11, 1)])
        UserLibrary.shared.set(scales: [scale], chords: [chord])
        defer { UserLibrary.shared.set(scales: [], chords: []) }
        #expect(ScaleLibrary.scale(id: "user-scale-test") == scale)
        #expect(ScaleLibrary.search("тестов").contains(scale))
        #expect(ChordLibrary.anyChord(id: "user-chord-test") == chord)
        #expect(chord.intervalSet == [0, 6, 7, 11])
        #expect(chord.spell(root: NoteName(.c)).map { NoteFormatter().string($0) } == ["C", "G", "B", "F♯"])
        #expect(chord.optionalDegrees == [DegreeLabel(5)])
    }
}
