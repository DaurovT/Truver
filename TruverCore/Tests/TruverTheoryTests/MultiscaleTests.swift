import Foundation
import Testing
@testable import TruverTheory

@Suite("Fanned frets (PR-7)")
struct MultiscaleTests {
    let fan = Multiscale.inches(27, 25.5, neutralFret: 7)

    @Test("Scale length runs linearly from the bass to the treble course")
    func lengths() {
        #expect(abs(fan.scaleLength(course: 0, courses: 8) - 685.8) < 0.01)
        #expect(abs(fan.scaleLength(course: 7, courses: 8) - 647.7) < 0.01)
        let ratios = fan.ratios(courses: 8)
        #expect(ratios.count == 8)
        #expect(ratios.first! > 1 && ratios.last! < 1)
        #expect(abs(ratios.reduce(0, +) / 8 - 1) < 1e-9)
    }

    @Test("The neutral fret is square; the nut and the 24th fret slant the opposite ways")
    func slant() {
        let n = 8
        #expect((0..<n).allSatisfy { abs(fan.fretPosition(course: $0, fret: 7, courses: n)) < 1e-9 })
        // The bass string is longer: its nut sits further from the neutral fret, its 24th fret further towards the bridge.
        #expect(fan.fretPosition(course: 0, fret: 0, courses: n) < fan.fretPosition(course: 7, fret: 0, courses: n))
        #expect(fan.fretPosition(course: 0, fret: 24, courses: n) > fan.fretPosition(course: 7, fret: 24, courses: n))
        // 12th fret is at half the scale on every string.
        let half = fan.fretPosition(course: 0, fret: 12, courses: n) - fan.fretPosition(course: 0, fret: 0, courses: n)
        #expect(abs(half - 685.8 / 2) < 0.01)
    }
}
