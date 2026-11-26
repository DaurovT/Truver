import Foundation
import Testing
@testable import TruverDSP

@Suite("Phase strobe (TU-10)")
struct PhaseStrobeTests {
    func measure(_ signal: [Float], target: Double, block: Int = 480) -> StrobeReading? {
        let strobe = PhaseStrobe(sampleRate: Signals.sampleRate)
        strobe.setTarget(target)
        var i = 0
        while i < signal.count {
            strobe.process(signal[i..<min(signal.count, i + block)])
            i += block
        }
        return strobe.reading()
    }

    @Test("0.1-cent class on a sustained note, sharp and flat, low B and high E", arguments: [(30.87, 0.3), (110.0, -0.25), (329.63, 0.1), (61.74, -1.7)])
    func precision(_ target: Double, _ cents: Double) throws {
        let played = target * pow(2, cents / 1200)
        let signal = Signals.add(Signals.tone(played, seconds: 2, decaySeconds: 4),
                                 Signals.noise(count: Int(2 * Signals.sampleRate), level: 0.002))
        let r = try #require(measure(signal, target: target))
        #expect(r.isStable)
        #expect(abs(r.cents - cents) < 0.1, "measured \(r.cents) for \(cents)")
    }

    @Test("A weak fundamental is read from a stronger harmonic")
    func weakFundamental() throws {
        let target = 41.2
        let signal = Signals.tone(target * pow(2, 0.4 / 1200), seconds: 2, harmonics: [0.05, 1, 0.6, 0.3])
        let r = try #require(measure(signal, target: target))
        #expect(r.harmonic >= 2)
        #expect(abs(r.cents - 0.4) < 0.1)
    }

    @Test("The ring turns at 360° × Δf: sharp clockwise, in tune it stands")
    func rotation() throws {
        let strobe = PhaseStrobe(sampleRate: Signals.sampleRate)
        strobe.setTarget(100)
        let sharp = Signals.tone(100.5, seconds: 2)   // Δf 0.5 Hz → 180°/s
        strobe.process(sharp[0..<48_000])
        let a = try #require(strobe.reading()).angle
        strobe.process(sharp[48_000..<57_600])             // +0.2 s → +36°
        let b = try #require(strobe.reading()).angle
        var turned = b - a
        if turned < 0 { turned += 360 }
        #expect(abs(turned - 36) < 3)
        // Noise only: no stable reading.
        #expect(measure(Signals.noise(count: 96_000, level: 0.05, seed: 7), target: 110)?.isStable != true)
    }
}
