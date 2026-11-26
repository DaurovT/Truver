import Testing
@testable import TruverDSP

@Suite("FB-13 drone (SND-5)")
struct DroneTests {
    private let rate = 48_000.0

    private func render(_ synth: NoteSynth, seconds: Double, from start: Int64 = 0) -> [Float] {
        var out: [Float] = []
        var buffer = [Float](repeating: 0, count: 256)
        var t = start
        while out.count < Int(seconds * rate) {
            for i in buffer.indices { buffer[i] = 0 }
            buffer.withUnsafeMutableBufferPointer { synth.render(adding: $0.baseAddress!, frameCount: 256, sampleTime: t) }
            out += buffer
            t += 256
        }
        return out
    }

    private func rms(_ x: ArraySlice<Float>) -> Double {
        (x.reduce(0.0) { $0 + Double($1 * $1) } / Double(max(1, x.count))).squareRoot()
    }

    @Test("Fades in, holds a steady level (no tremolo), fades out after stop")
    func envelope() {
        let synth = NoteSynth(sampleRate: rate)
        synth.startDrone(frequency: 82.41)
        let a = render(synth, seconds: 2)
        #expect(rms(a[0..<480]) < rms(a[48_000..<52_800]))            // first 10 ms quieter than the hold
        // Steady: windows of 8 whole periods across the second second differ by < 1 %.
        let w = Int((8 * rate / 82.41).rounded())
        let windows = stride(from: 48_000, to: 96_000 - w, by: w).map { rms(a[$0..<$0 + w]) }
        let spread = (windows.max()! - windows.min()!) / windows.max()!
        #expect(spread < 0.01)
        #expect(a.allSatisfy { abs($0) < 0.5 })
        synth.stopDrone()
        let b = render(synth, seconds: 1, from: 96_000)
        #expect(rms(b[b.count - 4_800..<b.count]) == 0)
        #expect(!synth.isDroning)
    }

    @Test("Pitch is the requested frequency (zero crossings)")
    func pitch() {
        let synth = NoteSynth(sampleRate: rate)
        synth.startDrone(frequency: 110)
        let a = Array(render(synth, seconds: 2)[48_000..<96_000])
        // Fundamental dominates: count upward crossings of a 1-pole low-passed copy.
        var y: Float = 0, prev: Float = 0, crossings = 0
        for x in a {
            y += 0.02 * (x - y)
            if prev <= 0 && y > 0 { crossings += 1 }
            prev = y
        }
        #expect(abs(crossings - 110) <= 1)
    }

    @Test("stopAll silences notes but keeps the drone")
    func independent() {
        let synth = NoteSynth(sampleRate: rate)
        synth.startDrone(frequency: 55)
        _ = render(synth, seconds: 0.5)
        synth.stopAll()
        #expect(synth.isDroning)
    }
}
