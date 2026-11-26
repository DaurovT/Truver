import Foundation
import Testing
@testable import TruverDSP

@Suite("Metronome (ME-1…ME-12)")
struct MetronomeTests {
    let sr = 48_000.0

    /// Runs the clock in render-sized blocks.
    func collect(_ clock: MetronomeClock, seconds: Double, block: Int = 512) -> [ClickEvent] {
        let end = Int64(seconds * sr)
        var events: [ClickEvent] = []
        var t: Int64 = 0
        while t < end {
            events += clock.events(from: t, frameCount: Int(min(Int64(block), end - t)))
            t += Int64(block)
        }
        return events
    }

    @Test("ME-1: beats land on exact samples across block boundaries")
    func sampleAccurate() {
        let clock = MetronomeClock(sampleRate: sr, settings: MeterSettings(bpm: 120))
        clock.start(atSample: 0)
        let events = collect(clock, seconds: 4, block: 441)
        #expect(events.count == 8)
        #expect(events.map(\.sampleTime) == (0..<8).map { Int64($0) * 24_000 })
        #expect(events.map(\.beat) == [0, 1, 2, 3, 0, 1, 2, 3])
        #expect(events.map(\.level) == [.strong, .normal, .normal, .normal, .strong, .normal, .normal, .normal])
    }

    @Test("Odd tempo: error from the ideal grid stays under one sample (NFR < 1 ms)")
    func oddTempo() {
        let clock = MetronomeClock(sampleRate: sr, settings: MeterSettings(bpm: 137))
        clock.start(atSample: 0)
        let events = collect(clock, seconds: 60)
        for (i, e) in events.enumerated() {
            let ideal = Double(i) * 60 / 137 * sr
            #expect(abs(Double(e.sampleTime) - ideal) <= 0.5)
        }
    }

    @Test("ME-3: triplets and swing")
    func subdivisionAndSwing() {
        let triplets = MetronomeClock(sampleRate: sr, settings: MeterSettings(bpm: 60, subdivision: 3))
        triplets.start(atSample: 0)
        let t = collect(triplets, seconds: 1)
        #expect(t.map(\.sampleTime) == [0, 16_000, 32_000])
        #expect(t.map(\.level) == [.strong, .soft, .soft])

        let swing = MetronomeClock(sampleRate: sr, settings: MeterSettings(bpm: 60, subdivision: 2, swing: 2.0 / 3))
        swing.start(atSample: 0)
        let s = collect(swing, seconds: 1)
        #expect(s.map(\.sampleTime) == [0, 32_000])
    }

    @Test("ME-3: grouping 2+2+3 sets accents")
    func grouping() {
        let settings = MeterSettings(numerator: 7, denominator: 8, grouping: [2, 2, 3])
        #expect(settings.accents == [.strong, .soft, .normal, .soft, .normal, .soft, .soft])
        #expect(settings.validationError == nil)
        var bad = settings
        bad.grouping = [3, 3]
        #expect(bad.validationError == "groupingSum")
    }

    @Test("ME-1: a tempo change applies from the next beat; a preset from the next bar")
    func changes() {
        let clock = MetronomeClock(sampleRate: sr, settings: MeterSettings(bpm: 60))
        clock.start(atSample: 0)
        _ = clock.events(from: 0, frameCount: 10)              // beat 0 scheduled
        clock.update(MeterSettings(bpm: 120))
        let next = collect(clock, seconds: 3).prefix(3).map(\.sampleTime)
        #expect(next.first == 48_000)                           // beat 1 at the old spacing
        #expect(Array(next.dropFirst()) == [72_000, 96_000])    // then 120 BPM

        let bar = MetronomeClock(sampleRate: sr, settings: MeterSettings(bpm: 60))
        bar.start(atSample: 0)
        _ = bar.events(from: 0, frameCount: 10)
        bar.update(MeterSettings(bpm: 120), at: .nextBar)
        let ev = collect(bar, seconds: 5)               // beats 1, 2, 3 of bar 0, then bar 1
        #expect(ev.prefix(3).map(\.bpm) == [60, 60, 60])
        #expect(ev[3].beat == 0 && ev[3].bpm == 120)
    }

    @Test("Разгон: +5 every 2 bars up to the target, then hold (6.1 п. 10)")
    func speedUp() {
        let clock = MetronomeClock(sampleRate: sr, settings: MeterSettings(bpm: 100),
                                   modes: TrainingModes(tempo: .speedUp(step: 5, every: .bars(2), target: 110)))
        clock.start(atSample: 0)
        let events = collect(clock, seconds: 20)
        let barTempos = events.filter { $0.beat == 0 && $0.tick == 0 }.map(\.bpm)
        #expect(Array(barTempos.prefix(7)) == [100, 100, 105, 105, 110, 110, 110])
        let notices = clock.drainNotices()
        #expect(notices.contains(.targetReached))
        #expect(notices.filter { $0 == .targetReached }.count == 1)
    }

    @Test("Два вперёд, один назад: +2N, −N")
    func twoForward() {
        let clock = MetronomeClock(sampleRate: sr, settings: MeterSettings(bpm: 100),
                                   modes: TrainingModes(tempo: .twoForwardOneBack(step: 4, everyBars: 1, target: 120)))
        clock.start(atSample: 0)
        let barTempos = collect(clock, seconds: 30).filter { $0.beat == 0 && $0.tick == 0 }.map(\.bpm)
        #expect(Array(barTempos.prefix(6)) == [100, 108, 104, 112, 108, 116])
        #expect(barTempos.last == 120)
    }

    @Test("Пропадающие такты: 2 on, 1 off growing to 2; silent ticks are flagged")
    func gapBars() {
        let clock = MetronomeClock(sampleRate: sr, settings: MeterSettings(bpm: 240),
                                   modes: TrainingModes(sound: .gapBars(on: 2, off: 1, offGrowth: 1, maxOff: 2)))
        clock.start(atSample: 0)
        let bars = Dictionary(grouping: collect(clock, seconds: 10), by: \.bar)
        let silent = (0..<9).map { bars[$0]!.allSatisfy(\.isSilent) }
        #expect(silent == [false, false, true, false, false, true, true, false, false])
        let notices = clock.drainNotices()
        #expect(notices.first == .silentBarsStarted)
    }

    @Test("Быстро / медленно: two bars slow, two bars fast, in a loop")
    func fastSlow() {
        let clock = MetronomeClock(sampleRate: sr, settings: MeterSettings(bpm: 150),
                                   modes: TrainingModes(tempo: .fastSlow(slow: 90, fast: 160, everyBars: 2)))
        clock.start(atSample: 0)
        let barTempos = collect(clock, seconds: 40).filter { $0.beat == 0 && $0.tick == 0 }.map(\.bpm)
        #expect(Array(barTempos.prefix(8)) == [90, 90, 160, 160, 90, 90, 160, 160])
        #expect(clock.drainNotices().contains(.tempoChanged(160)))
    }

    @Test("Случайный пропуск: beat 1 never drops, others drop about P of the time, subdivisions with them")
    func randomMute() {
        var settings = MeterSettings(bpm: 240)
        settings.subdivision = 2
        let clock = MetronomeClock(sampleRate: sr, settings: settings, modes: TrainingModes(sound: .randomMute(probability: 0.3)))
        clock.seedRandom(42)
        clock.start(atSample: 0)
        let events = collect(clock, seconds: 120)
        #expect(events.filter { $0.beat == 0 }.allSatisfy { !$0.isSilent })
        let beats = Dictionary(grouping: events.filter { $0.beat > 0 }, by: { $0.bar * 4 + $0.beat })
        #expect(beats.values.allSatisfy { Set($0.map(\.isSilent)).count == 1 })
        let dropped = Double(beats.values.filter { $0[0].isSilent }.count) / Double(beats.count)
        #expect(abs(dropped - 0.3) < 0.05)
        let none = MetronomeClock(sampleRate: sr, settings: settings, modes: TrainingModes(sound: .randomMute(probability: 0)))
        none.start(atSample: 0)
        #expect(collect(none, seconds: 4).allSatisfy { !$0.isSilent })
    }

    @Test("Перенос щелчка: backbeats, offbeats, downbeat")
    func displaced() {
        func audible(_ pattern: ClickPattern) -> [(Int, Int)] {
            let clock = MetronomeClock(sampleRate: sr, settings: MeterSettings(bpm: 60),
                                       modes: TrainingModes(sound: .displacedClick(pattern)))
            clock.start(atSample: 0)
            return collect(clock, seconds: 4).filter { !$0.isSilent }.map { ($0.beat, $0.tick) }
        }
        #expect(audible(.backbeats).map(\.0) == [1, 3])
        #expect(audible(.downbeat).map(\.0) == [0])
        let off = audible(.offbeats)
        #expect(off.count == 4 && off.allSatisfy { $0.1 == 1 })
    }

    @Test("Лесенка делений: 1 → 2 → 3 → 4 every bar")
    func ladder() {
        let clock = MetronomeClock(sampleRate: sr, settings: MeterSettings(bpm: 240),
                                   modes: TrainingModes(subdivision: .ladder(steps: [1, 2, 3, 4], barsPerStep: 1)))
        clock.start(atSample: 0)
        let bars = Dictionary(grouping: collect(clock, seconds: 5), by: \.bar)
        #expect((0..<5).map { bars[$0]!.first!.subdivision } == [1, 2, 3, 4, 1])
    }

    @Test("ME-2: tap tempo averages the last taps and resets after a pause")
    func tapTempo() {
        var tap = TapTempo()
        #expect(tap.tap(at: 0) == nil)
        #expect(tap.tap(at: 0.5) == nil)
        #expect(tap.tap(at: 1.0) == nil)
        #expect(tap.tap(at: 1.5) == 120)
        #expect(tap.tap(at: 5) == nil)
    }

    @Test("6.1 п. 9: no more than 3 flashes per second")
    func flashes() {
        #expect(FlashPolicy.rule(for: MeterSettings(bpm: 120)) == .everyBeat)
        #expect(FlashPolicy.rule(for: MeterSettings(bpm: 240)) == .strongBeats)
        #expect(FlashPolicy.rule(for: MeterSettings(bpm: 400, numerator: 4)) == .strongBeats)
        #expect(FlashPolicy.rule(for: MeterSettings(bpm: 400, numerator: 1, denominator: 4)) == .everyNthBar(3))
        for bpm in stride(from: 20.0, through: 400, by: 7) {
            for numerator in [1, 3, 4, 7] {
                let settings = MeterSettings(bpm: bpm, numerator: numerator)
                let clock = MetronomeClock(sampleRate: sr, settings: settings)
                clock.start(atSample: 0)
                let rule = FlashPolicy.rule(for: settings)
                let flashes = collect(clock, seconds: 6).filter { FlashPolicy.flashes($0, rule: rule, accents: settings.accents) }
                #expect(Double(flashes.count) / 6 <= 3.2, "bpm \(bpm), \(numerator) beats")
            }
        }
    }

    @Test("Renderer: click starts on its sample, silent ticks render nothing")
    func renderer() {
        let clock = MetronomeClock(sampleRate: sr, settings: MeterSettings(bpm: 120))
        let renderer = MetronomeRenderer(clock: clock, sounds: .synthesized(sampleRate: sr))
        clock.start(atSample: 1000)
        var buffer = [Float](repeating: 0, count: 2048)
        var seen: [ClickEvent] = []
        buffer.withUnsafeMutableBufferPointer { ptr in
            renderer.render(into: ptr.baseAddress!, frameCount: 2048, sampleTime: 0) { seen.append($0) }
        }
        #expect(seen.map(\.sampleTime) == [1000])
        #expect(buffer[..<1000].allSatisfy { $0 == 0 })
        #expect(buffer[1001..<1100].contains { abs($0) > 0.01 })
    }
}

@Suite("Note synth")
struct NoteSynthTests {
    @Test("Reference tone has the exact pitch and stops after its duration")
    func referencePitch() throws {
        let sr = 48_000.0
        let synth = NoteSynth(sampleRate: sr)
        synth.schedule(frequency: 61.735, at: 0, kind: .reference(duration: 0.5))
        var buffer = [Float](repeating: 0, count: Int(0.8 * sr))
        buffer.withUnsafeMutableBufferPointer { synth.render(adding: $0.baseAddress!, frameCount: $0.count, sampleTime: 0) }
        let window = 2 * Int(sr / 61.735) + 8, maxLag = Int(sr / 50)
        let frame = Array(buffer[4000..<(4000 + window + maxLag)]).withUnsafeBufferPointer {
            YINFrame(samples: $0, sampleRate: sr, window: window, maxLag: maxLag)
        }
        let estimate = try #require(frame.estimate(minLag: 20, threshold: 0.15))
        #expect(abs(1200 * log2(estimate.frequency / 61.735)) < 0.5)
        #expect(buffer[Int(0.7 * sr)...].allSatisfy { $0 == 0 })
        #expect(!synth.isPlaying)
    }

    @Test("A pluck starts on its sample and decays")
    func pluck() {
        let synth = NoteSynth(sampleRate: 48_000)
        synth.schedule(frequency: 440, at: 1000)
        var buffer = [Float](repeating: 0, count: 4096)
        buffer.withUnsafeMutableBufferPointer { synth.render(adding: $0.baseAddress!, frameCount: 4096, sampleTime: 0) }
        #expect(buffer[..<1000].allSatisfy { $0 == 0 })
        #expect(buffer[1100..<1300].contains { abs($0) > 0.01 })
    }

    @Test("Next bar start of a running clock")
    func nextBar() {
        let clock = MetronomeClock(sampleRate: 48_000, settings: MeterSettings(bpm: 120))
        clock.start(atSample: 0)
        _ = clock.events(from: 0, frameCount: 30_000)   // beats 0 and 1 scheduled
        #expect(clock.nextBarStart() == 96_000)
    }
}

@Suite("Lock-free ring")
struct RingTests {
    @Test func orderAndOverflow() {
        let ring = SPSCRing<Int>(capacity: 4, filler: 0)
        for i in 0..<4 { #expect(ring.push(i)) }
        #expect(!ring.push(99))
        #expect(ring.droppedCount == 1)
        #expect(ring.drain() == [0, 1, 2, 3])
        #expect(ring.drain().isEmpty)
        ring.push(5)
        #expect(ring.drain() == [5])
    }

    @Test("A producer and a consumer on different threads lose nothing in order")
    func concurrent() async {
        let ring = SPSCRing<Int>(capacity: 256, filler: 0)
        let total = 200_000
        let producer = Task.detached {
            var i = 0
            while i < total { if ring.push(i) { i += 1 } }
        }
        var received: [Int] = []
        while received.count < total {
            received += ring.drain()
            await Task.yield()
        }
        await producer.value
        #expect(received == Array(0..<total))
    }
}

@Suite("Song map and second track (ME-8)")
struct SongMapTests {
    let sr = 48_000.0

    func collect(_ clock: MetronomeClock, seconds: Double) -> [ClickEvent] {
        var events: [ClickEvent] = []
        var t: Int64 = 0
        while t < Int64(seconds * sr) { events += clock.events(from: t, frameCount: 512); t += 512 }
        return events
    }

    @Test("Sections change tempo and meter at their bar lines; count-in first; stop without a loop")
    func song() {
        let sections = [SongSection(name: "Вступление", bpm: 120, numerator: 4, bars: 2),
                        SongSection(name: "Риф", bpm: 160, numerator: 7, denominator: 8, bars: 1)]
        let clock = MetronomeClock(sampleRate: sr, settings: MeterSettings(bpm: 90),
                                   modes: TrainingModes(tempo: .songMap(sections: sections, loop: false, countIn: true)))
        clock.start(atSample: 0)
        let bars = Dictionary(grouping: collect(clock, seconds: 12).filter { $0.track == 0 && $0.tick == 0 }, by: \.bar)
        // Bar 0 count-in and bars 1–2 at 120 in 4/4, bar 3 at 160 in 7/8.
        #expect(bars[0]?.count == 4 && bars[0]?.first?.bpm == 120)
        #expect(bars[2]?.count == 4 && bars[2]?.first?.bpm == 120)
        #expect(bars[3]?.count == 7 && bars[3]?.first?.bpm == 160)
        let notices = clock.drainNotices()
        #expect(notices.contains(.sectionChanged(0)) && notices.contains(.sectionChanged(1)))
        #expect(notices.contains(.songEnded))
    }

    @Test("Loop goes back to the first section")
    func loop() {
        let sections = [SongSection(name: "A", bpm: 200, numerator: 4, bars: 1), SongSection(name: "B", bpm: 100, numerator: 3, bars: 1)]
        let clock = MetronomeClock(sampleRate: sr, modes: TrainingModes(tempo: .songMap(sections: sections, loop: true, countIn: false)))
        clock.start(atSample: 0)
        let downbeats = collect(clock, seconds: 10).filter { $0.track == 0 && $0.beat == 0 && $0.tick == 0 }.map(\.bpm)
        #expect(Array(downbeats.prefix(4)) == [200, 100, 200, 100])
    }

    @Test("3 against 4: three even second-track pulses per bar, in time order with the beats")
    func polyrhythm() {
        var settings = MeterSettings(bpm: 60)
        settings.poly = PolyTrack(kind: .rhythm, count: 3)
        let clock = MetronomeClock(sampleRate: sr, settings: settings)
        clock.start(atSample: 0)
        let events = collect(clock, seconds: 4)
        let poly = events.filter { $0.track == 1 }
        #expect(poly.map(\.sampleTime) == [0, 64_000, 128_000])
        #expect(poly.first?.level == .strong)
        #expect(events.map(\.sampleTime) == events.map(\.sampleTime).sorted())
    }

    @Test("Polymeter 3 over 4/4: a second-track click every third beat across bar lines")
    func polymeter() {
        var settings = MeterSettings(bpm: 120)
        settings.poly = PolyTrack(kind: .meter, count: 3)
        let clock = MetronomeClock(sampleRate: sr, settings: settings)
        clock.start(atSample: 0)
        let poly = collect(clock, seconds: 6).filter { $0.track == 1 }
        #expect(Array(poly.map { $0.sampleTime / 24_000 }.prefix(5)) == [0, 3, 6, 9, 12])
    }
}
