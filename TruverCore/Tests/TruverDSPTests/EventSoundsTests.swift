import Testing
@testable import TruverDSP

@Suite("SND-3 event signals")
struct EventSoundsTests {
    private let rate = 48_000.0

    private func peak(_ x: [Float]) -> Float { x.reduce(0) { max($0, abs($1)) } }

    @Test("6 dB below the strong click of every set", arguments: ClickSounds.Kind.allCases)
    func level(kind: ClickSounds.Kind) {
        let clicks = ClickSounds.make(kind, sampleRate: rate)
        for sound in EventSound.allCases {
            let s = EventSounds.make(sound, sampleRate: rate, clicks: clicks)
            #expect(abs(peak(s) - 0.5 * peak(clicks.strong)) < 0.001)
        }
    }

    @Test("Tonal and long — unlike a click; the two events differ")
    func shape() {
        let clicks = ClickSounds.make(.click, sampleRate: rate)
        let target = EventSounds.make(.targetReached, sampleRate: rate, clicks: clicks)
        let timer = EventSounds.make(.timerEnded, sampleRate: rate, clicks: clicks)
        #expect(Double(target.count) / rate >= 0.25)
        #expect(Double(timer.count) / rate >= 0.25)
        #expect(clicks.strong.count * 8 < target.count)
        #expect(target != timer)
        // Ends silently (no click at the end of the buffer).
        #expect(abs(target.last ?? 1) < 1e-4 && abs(timer.last ?? 1) < 1e-4)
    }

    @Test("The renderer mixes an event at its sample time with the click volume, metronome stopped")
    func renderer() {
        let clock = MetronomeClock(sampleRate: rate)
        let clicks = ClickSounds.make(.click, sampleRate: rate)
        let r = MetronomeRenderer(clock: clock, sounds: clicks)
        r.volume = 0.6
        let s = EventSounds.make(.timerEnded, sampleRate: rate, clicks: clicks)
        r.scheduleEvent(.timerEnded, samples: s, at: 1000)
        var out = [Float](repeating: 0, count: 512)
        var rendered: [Float] = []
        var t: Int64 = 0
        while t < Int64(s.count + 2000) {
            out.withUnsafeMutableBufferPointer { r.render(into: $0.baseAddress!, frameCount: 512, sampleTime: t) }
            rendered += out
            t += 512
        }
        #expect(rendered[..<1000].allSatisfy { $0 == 0 })
        #expect(abs(rendered[1000 + 300] - s[300] * 0.6) < 1e-6)
        #expect(!r.isPlayingEvent)
    }
}
