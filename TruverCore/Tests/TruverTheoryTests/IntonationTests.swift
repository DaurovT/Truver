import Foundation
import Testing
@testable import TruverTheory

@Suite("Intonation check (TU-11)")
struct IntonationTests {
    @Test("A sharp octave moves the saddle away from the neck, about 2.7 c per mm on 648 mm")
    func shift() {
        let open = 82.41
        let cents = Intonation.error(open: open, twelfth: 2 * open * pow(2, 6.0 / 1200))
        #expect(abs(cents - 6) < 1e-9)
        #expect(Intonation.verdict(cents: cents) == .awayFromNeck)
        #expect(Intonation.verdict(cents: -3) == .towardsNeck)
        #expect(Intonation.verdict(cents: 1.5) == .ok)
        let mm = Intonation.saddleShift(cents: 2.67, scaleLength: 648)
        #expect(abs(mm - 1) < 0.01)
        // Exact geometry: moving the saddle 1 mm back lowers the octave by that much.
        let l = 648.0
        let after = 1200 * log2((l + 1) / (l / 2 + 1) / 2)
        #expect(abs(after + 2.67) < 0.02)
    }

    @Test("Steady readings: a median only once they agree")
    func steady() {
        #expect(Intonation.steadyFrequency(Array(repeating: 110, count: 10)) == nil)
        let wobbly = (0..<20).map { 110 * pow(2, Double($0 % 2 == 0 ? 8 : -8) / 1200) }
        #expect(Intonation.steadyFrequency(wobbly) == nil)
        let ok = (0..<20).map { 110 * pow(2, Double($0 % 3 - 1) / 1200) }
        #expect(abs(Intonation.steadyFrequency(ok)! - 110) < 0.1)
    }
}
