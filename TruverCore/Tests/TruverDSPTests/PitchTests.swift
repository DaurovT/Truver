import Foundation
import Testing
@testable import TruverDSP
@testable import TruverTheory

@Suite("YIN and octave check")
struct YINTests {
    func analyze(_ samples: [Float], window: Int, maxLag: Int, minLag: Int = 2) -> (YINFrame, YINEstimate?) {
        let frame = samples.withUnsafeBufferPointer {
            YINFrame(samples: $0, sampleRate: Signals.sampleRate, window: window, maxLag: maxLag)
        }
        return (frame, frame.estimate(minLag: minLag, threshold: 0.15))
    }

    @Test("TU-1: ≤ 1 cent on stable harmonic signals, 30–1400 Hz",
          arguments: [30.87, 41.2, 46.25, 55, 82.41, 110, 146.8, 196, 246.9, 329.6, 440, 659.3, 880, 1100, 1400])
    func accuracy(frequency: Double) throws {
        let sr = Signals.sampleRate
        let period = sr / frequency
        let window = Int((2 * period).rounded(.up)) + 64
        let maxLag = Int(period * 1.4) + 4
        let samples = Signals.add(Signals.tone(frequency, seconds: 0.25), Signals.noise(count: Int(0.25 * sr)))
        let (_, estimate) = analyze(Array(samples[2000...]), window: window, maxLag: maxLag)
        let found = try #require(estimate)
        #expect(abs(Signals.cents(found.frequency, frequency)) < 1, "\(frequency) Hz → \(found.frequency)")
    }

    /// Low B with a weak fundamental and weak odd harmonics: plain YIN lands an octave up (B1).
    static let weakFundamental: [Double] = [0.08, 1.0, 0.05, 0.6, 0.03, 0.3]

    @Test("TU-4: B0 with a weak fundamental is corrected down from B1")
    func octaveDown() throws {
        let b0 = Signals.hz("B0")
        let sr = Signals.sampleRate
        let samples = Signals.add(Signals.tone(b0, seconds: 0.3, harmonics: Self.weakFundamental), Signals.noise(count: Int(0.3 * sr)))
        let maxLag = Int(sr / (b0 * 0.84)) + 2
        let window = Int(2 * sr / b0) + 1
        let (frame, estimate) = analyze(Array(samples[2000...]), window: window, maxLag: maxLag)
        let raw = try #require(estimate)
        #expect(abs(Signals.cents(raw.frequency, 2 * b0)) < 5, "plain YIN should find B1 here, got \(raw.frequency)")
        let corrected = OctaveCheck().apply(raw, frame: frame, minFrequency: 25)
        #expect(corrected.factor == 2)
        #expect(abs(Signals.cents(corrected.estimate.frequency, b0)) < 1)
    }

    @Test("TU-4: a real B1 is not pushed down (both lags near zero)")
    func trueHighNoteStays() throws {
        let b1 = Signals.hz("B1")
        let sr = Signals.sampleRate
        let samples = Signals.add(Signals.tone(b1, seconds: 0.3), Signals.noise(count: Int(0.3 * sr)))
        let b0 = b1 / 2
        let (frame, estimate) = analyze(Array(samples[2000...]), window: Int(2 * sr / b0) + 1, maxLag: Int(sr / (b0 * 0.84)) + 2)
        let raw = try #require(estimate)
        let corrected = OctaveCheck().apply(raw, frame: frame, minFrequency: 25)
        #expect(corrected.factor == 1)
        #expect(abs(Signals.cents(corrected.estimate.frequency, b1)) < 1)
    }
}

@Suite("Pitch tracker (TU-2…TU-8)")
struct TrackerTests {
    func tuning(_ id: String) -> Tuning { TuningTemplates.template(id: id)!.makeTuning() }

    /// Feeds `silenceBefore` seconds of noise, then the note, in 256-sample blocks.
    func run(_ tracker: PitchTracker, note: [Float], silenceBefore: Double = 0.2) -> (updates: [TunerUpdate], attack: Double) {
        let lead = Signals.noise(count: Int(silenceBefore * Signals.sampleRate), level: 0.0002)
        let signal = lead + Signals.add(note, Signals.noise(count: note.count, level: 0.0002, seed: 7))
        var updates: [TunerUpdate] = []
        var i = 0
        while i < signal.count {
            let end = min(i + 256, signal.count)
            updates += tracker.process(Array(signal[i..<end]))
            i = end
        }
        return (updates, silenceBefore)
    }

    func firstReading(_ updates: [TunerUpdate], where match: (TunerReading) -> Bool) -> TunerUpdate? {
        updates.first { if case .reading(let r) = $0.display { return match(r) } else { return false } }
    }

    func string(_ target: TunerTarget) -> StringRef? {
        if case let .string(ref, _, _) = target { return ref }
        return nil
    }

    @Test("NFR: E2 on a 6-string reads within 120 ms of the attack")
    func latencyE2() throws {
        let tracker = PitchTracker(configuration: TunerConfiguration(sampleRate: Signals.sampleRate), tuning: tuning("g6-standard-e"))
        let (updates, attack) = run(tracker, note: Signals.tone(Signals.hz("E2"), seconds: 0.6, decaySeconds: 2))
        let first = try #require(firstReading(updates) { string($0.target) == StringRef(course: 0) })
        #expect(first.time - attack <= 0.120, "first reading after \(first.time - attack) s")
        let last = try #require(updates.last)
        guard case .reading(let r) = last.display else { Issue.record("no reading at the end"); return }
        #expect(abs(r.target.deviationCents) < 1)
    }

    @Test("NFR: E2 on a 9-string (C♯ standard) still reads within 120 ms")
    func latencyE2NineString() throws {
        let tracker = PitchTracker(configuration: TunerConfiguration(sampleRate: Signals.sampleRate), tuning: tuning("g9-standard-cs"))
        let (updates, attack) = run(tracker, note: Signals.tone(Signals.hz("E2"), seconds: 0.6, decaySeconds: 2))
        let first = try #require(firstReading(updates) { string($0.target) == StringRef(course: 3) })
        #expect(first.time - attack <= 0.120, "first reading after \(first.time - attack) s")
    }

    @Test("TU-2 + TU-4 + TU-4a: Drop B, B0 with a weak fundamental — name hidden, then B0 within 200 ms")
    func dropBLowString() throws {
        let tracker = PitchTracker(configuration: TunerConfiguration(sampleRate: Signals.sampleRate), tuning: tuning("g9-drop-b"))
        let (updates, attack) = run(tracker, note: Signals.tone(Signals.hz("B0"), seconds: 0.8,
                                                                 harmonics: YINTests.weakFundamental, decaySeconds: 3))
        // Never shows the B1 string (course 2) for this note.
        #expect(firstReading(updates) { string($0.target) == StringRef(course: 2) } == nil)
        let first = try #require(firstReading(updates) { string($0.target) == StringRef(course: 0) })
        #expect(first.time - attack <= 0.200, "first B0 reading after \(first.time - attack) s")
        let hiddenBefore = updates.filter { $0.time < first.time && $0.time > attack + 0.05 }
        #expect(hiddenBefore.allSatisfy { $0.display == .listening })
    }

    @Test("TU-4a: a real B1 on Drop B stays on the B1 string")
    func dropBThirdString() throws {
        let tracker = PitchTracker(configuration: TunerConfiguration(sampleRate: Signals.sampleRate), tuning: tuning("g9-drop-b"))
        let (updates, _) = run(tracker, note: Signals.tone(Signals.hz("B1"), seconds: 0.8, decaySeconds: 3))
        let readings = updates.compactMap { u -> StringRef? in
            if case .reading(let r) = u.display { return string(r.target) } else { return nil }
        }
        #expect(!readings.isEmpty)
        #expect(readings.allSatisfy { $0 == StringRef(course: 2) })
    }

    @Test("5-string bass in Drop F♯: F♯0 (23 Hz) is read")
    func lowestBassString() throws {
        let tracker = PitchTracker(configuration: TunerConfiguration(sampleRate: Signals.sampleRate), tuning: tuning("b5-drop-fs"))
        let (updates, _) = run(tracker, note: Signals.tone(Signals.hz("F#0"), seconds: 2, decaySeconds: 4))
        let readings = updates.compactMap { u -> TunerReading? in if case .reading(let r) = u.display { return r } else { return nil } }
        let last = try #require(readings.last)
        #expect(string(last.target) == StringRef(course: 0))
        #expect(abs(last.target.deviationCents) < 3)
    }

    @Test("Silence is idle; attack is ignored at first")
    func idleAndListening() {
        let tracker = PitchTracker(configuration: TunerConfiguration(sampleRate: Signals.sampleRate), tuning: tuning("g6-standard-e"))
        let (updates, attack) = run(tracker, note: Signals.tone(Signals.hz("A2"), seconds: 0.3, decaySeconds: 2))
        #expect(updates.filter { $0.time < attack }.allSatisfy { $0.display == .idle })
        let justAfter = updates.first { $0.time > attack }
        #expect(justAfter?.display == .listening)
    }

    @Test("TU-8: string tuned after 0.3 s in ±3 cents; all strings → allStringsTuned")
    func inTune() {
        let tuning = tuning("b4-standard")
        let tracker = PitchTracker(configuration: TunerConfiguration(sampleRate: Signals.sampleRate), tuning: tuning)
        var events: [TunerEvent] = []
        for note in ["E1", "A1", "D2", "G2"] {
            let (updates, _) = run(tracker, note: Signals.tone(Signals.hz(note), seconds: 0.9), silenceBefore: 0.15)
            events += updates.flatMap(\.events)
        }
        #expect(events.filter { if case .stringTuned = $0 { return true } else { return false } }.count == 4)
        #expect(events.last == .allStringsTuned)
        #expect(tracker.tunedStrings.count == 4)
    }

    @Test("TU-8: a string 10 cents off is not marked")
    func notInTune() {
        let tracker = PitchTracker(configuration: TunerConfiguration(sampleRate: Signals.sampleRate), tuning: tuning("g6-standard-e"))
        let (updates, _) = run(tracker, note: Signals.tone(Signals.hz("A2") * pow(2, 10 / 1200), seconds: 0.9))
        #expect(updates.flatMap(\.events).isEmpty)
    }

    @Test("TU-6 through the tracker: E2 on Drop D shows E with a hint for D2")
    func retuneHint() throws {
        let tracker = PitchTracker(configuration: TunerConfiguration(sampleRate: Signals.sampleRate), tuning: tuning("g6-drop-d"))
        let (updates, _) = run(tracker, note: Signals.tone(Signals.hz("E2"), seconds: 0.6, decaySeconds: 2))
        guard case .reading(let r) = try #require(updates.last).display,
              case let .chromatic(nearest, _, hint) = r.target else { Issue.record("expected chromatic"); return }
        #expect(nearest.nearestMIDI == 40)
        #expect(hint?.string == StringRef(course: 0))
    }

    @Test("Manual mode shows a large deviation")
    func manual() throws {
        let tracker = PitchTracker(configuration: TunerConfiguration(sampleRate: Signals.sampleRate), tuning: tuning("g6-standard-e"),
                                   mode: .manual(course: 0, string: 0))
        let (updates, _) = run(tracker, note: Signals.tone(Signals.hz("C2"), seconds: 0.6, decaySeconds: 2))
        guard case .reading(let r) = try #require(updates.last).display else { Issue.record("no reading"); return }
        #expect(abs(r.target.deviationCents + 400) < 2)
    }

    @Test("A4 calibration shifts readings (PR-5)")
    func calibration() throws {
        var config = TunerConfiguration(sampleRate: Signals.sampleRate)
        config.a4 = 432
        let tracker = PitchTracker(configuration: config, tuning: tuning("g6-standard-e"))
        let a2at432 = 432.0 / 4
        let (updates, _) = run(tracker, note: Signals.tone(a2at432, seconds: 0.6, decaySeconds: 2))
        guard case .reading(let r) = try #require(updates.last).display else { Issue.record("no reading"); return }
        #expect(string(r.target) == StringRef(course: 1))
        #expect(abs(r.target.deviationCents) < 1)
    }
}

@Suite("Motion spec behaviour in the core")
struct MotionSpecTests {
    func tuning() -> Tuning { TuningTemplates.template(id: "g6-standard-e")!.makeTuning() }

    func readings(_ tracker: PitchTracker, cents: Double, seconds: Double, startSilence: Bool) -> [TunerReading] {
        let a2 = Signals.hz("A2") * pow(2, cents / 1200)
        var signal = startSilence ? Signals.noise(count: Int(0.2 * Signals.sampleRate), level: 0.0002) : []
        signal += Signals.tone(a2, seconds: seconds)
        var out: [TunerReading] = []
        var i = 0
        while i < signal.count {
            for u in tracker.process(Array(signal[i..<min(i + 256, signal.count)])) {
                if case .reading(let r) = u.display { out.append(r) }
            }
            i += 256
        }
        return out
    }

    @Test("«В строю»: on after 0.3 s within ±3 c, stays at +4 c, never turns on when it starts at +4 c")
    func hysteresis() {
        let tracker = PitchTracker(configuration: TunerConfiguration(sampleRate: Signals.sampleRate), tuning: tuning())
        let first = readings(tracker, cents: 1, seconds: 0.8, startSilence: true)
        #expect(first.last?.isInTune == true)
        #expect(first.prefix(4).allSatisfy { !$0.isInTune })

        // A fresh note at +4 c: inside the exit band but outside the entry band → never in tune.
        let tracker2 = PitchTracker(configuration: TunerConfiguration(sampleRate: Signals.sampleRate), tuning: tuning())
        #expect(readings(tracker2, cents: 4, seconds: 0.8, startSilence: true).allSatisfy { !$0.isInTune })
    }

    @Test("Pause keeps the last display while a haptic pulse would be heard")
    func pause() {
        let tracker = PitchTracker(configuration: TunerConfiguration(sampleRate: Signals.sampleRate), tuning: tuning())
        _ = readings(tracker, cents: 0, seconds: 0.5, startSilence: true)
        tracker.pauseAnalysis(seconds: 0.05)
        // A loud burst during the pause must not change the display.
        let burst = Signals.noise(count: 1200, level: 0.5, seed: 9)
        let updates = tracker.process(burst)
        #expect(updates.allSatisfy { if case .reading = $0.display { return true } else { return false } })
    }

    @Test("Strobe band: 6 °/s per cent, capped at 300 °/s, still within ±1 c")
    func strobe() {
        var strobe = StrobeRotation()
        #expect(strobe.speed(cents: 0.8) == 0)
        #expect(strobe.speed(cents: 10) == 60)
        #expect(strobe.speed(cents: -80) == -300)
        strobe.advance(cents: 10, dt: 1)
        strobe.advance(cents: -20, dt: 1)
        #expect(strobe.angle == 300)
    }
}
