#if canImport(Darwin)
import Darwin
#elseif canImport(Android)
import Android
#elseif canImport(Glibc)
import Glibc
#endif
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// One tick of the metronome on the audio timeline (ME-12).
public struct ClickEvent: Hashable, Sendable {
    /// Sample time of the tick on the output timeline (before output latency).
    public var sampleTime: Int64
    /// Bar number since start (0-based).
    public var bar: Int
    /// Beat within the bar (0-based).
    public var beat: Int
    /// Subdivision within the beat; 0 is the beat itself.
    public var tick: Int
    public var level: AccentLevel
    /// Muted by a mode: no sound, flash, vibration or watch tap on this tick (6.1 п. 8).
    public var isSilent: Bool
    public var bpm: Double
    public var subdivision: Int
    /// The beat itself is a rest of the rhythmic figure (silent, but the bar goes on — not a silent bar).
    public var isRest: Bool = false
    /// 0 — the main pulse; 1 — the ME-8 second track (own sound, no flash or beat highlight).
    public var track: Int = 0
}

extension ClickEvent {
    /// Filler value for preallocated buffers.
    public static let placeholder = ClickEvent(sampleTime: 0, bar: 0, beat: 0, tick: 0, level: .off, isSilent: true, bpm: 0, subdivision: 1)
}

/// Things the screen reports while playing (6.2.6).
public enum MetronomeNotice: Hashable, Sendable {
    case tempoChanged(Double)
    case targetReached
    case subdivisionChanged(Int)
    case silentBarsStarted
    case silentBarsEnded
    /// Карта песни: section `index` begins (also at the start, after the count-in).
    case sectionChanged(Int)
    /// Карта песни without a loop: the last section ended (the app stops).
    case songEnded
}

public enum ApplyMoment: Sendable {
    /// Tempo and meter changes apply from the next beat (ME-1).
    case nextBeat
    /// Presets loaded while playing apply from the next bar (6.2.6).
    case nextBar
}

/// Sample-accurate metronome clock (ME-1). No OS timers: the audio render callback asks for the ticks that
/// fall into each buffer. Modes change parameters at bar boundaries (ME-6).
///
/// Not thread-safe: owned by the render thread; settings changes are passed in through `update`.
public final class MetronomeClock {
    public let sampleRate: Double
    public private(set) var settings: MeterSettings
    public private(set) var modes: TrainingModes
    public private(set) var isRunning = false

    private var pending: (settings: MeterSettings, moment: ApplyMoment)?
    private var nextBeatTime = 0.0
    private var beat = 0
    private var bar = -1
    private var queue: [ClickEvent] = []
    private var notices: [MetronomeNotice] = []

    // Mode state
    private var barSilent = false
    private var barsSinceTempoChange = 0
    private var lastTempoChangeTime = 0.0
    private var forwardPhase = true
    private var targetReported = false
    private var ladderIndex = 0
    private var ladderBars = 0
    private var gapPosition = 0
    private var gapOff = 0
    private var fastPhase = false
    private var sectionIndex = 0
    private var sectionBarsLeft = 0
    private var songEnded = false
    private var totalBeats = 0
    /// Deterministic generator for «Случайный пропуск» (no allocation, no locks on the render thread).
    private var random = SplitMix64(seed: 0x7275_7665_7200)

    /// Seed for «Случайный пропуск»; tests fix it, the app leaves the default.
    public func seedRandom(_ seed: UInt64) { random = SplitMix64(seed: seed) }

    /// Index and start time of the next beat that has not been scheduled yet.
    var upcomingBeatIndex: Int { beat }
    var upcomingBeatTime: Double { nextBeatTime }

    public init(sampleRate: Double, settings: MeterSettings = MeterSettings(), modes: TrainingModes = .none) {
        self.sampleRate = sampleRate
        self.settings = settings
        self.modes = modes
        queue.reserveCapacity(32)
        notices.reserveCapacity(16)
    }

    public func start(atSample time: Int64) {
        isRunning = true
        nextBeatTime = Double(time)
        beat = 0
        bar = -1
        queue.removeAll(keepingCapacity: true)
        resetModeState()
        lastTempoChangeTime = Double(time)
    }

    public func stop() {
        isRunning = false
        queue.removeAll(keepingCapacity: true)
    }

    public func update(_ newSettings: MeterSettings, at moment: ApplyMoment = .nextBeat) {
        if isRunning { pending = (newSettings, moment) } else { settings = newSettings }
    }

    public func setModes(_ newModes: TrainingModes) {
        modes = newModes
        resetModeState()
    }

    /// Notices produced since the last call.
    public func drainNotices() -> [MetronomeNotice] {
        defer { notices.removeAll(keepingCapacity: true) }
        return notices
    }

    /// Calls `body` for every tick with `sampleTime` in `start ..< start + frameCount`, in time order.
    public func forEachEvent(from start: Int64, frameCount: Int, _ body: (ClickEvent) -> Void) {
        guard isRunning else { return }
        let end = start + Int64(frameCount)
        while true {
            if queue.isEmpty {
                guard Int64(nextBeatTime.rounded()) < end else { return }
                scheduleBeat()
            }
            guard let first = queue.first, first.sampleTime < end else { return }
            queue.removeFirst()
            if first.sampleTime >= start { body(first) }
        }
    }

    /// Convenience for tests and offline rendering (allocates).
    public func events(from start: Int64, frameCount: Int) -> [ClickEvent] {
        var result: [ClickEvent] = []
        forEachEvent(from: start, frameCount: frameCount) { result.append($0) }
        return result
    }

    // MARK: - Scheduling

    private func scheduleBeat() {
        if let p = pending, p.moment == .nextBeat || beat == 0 {
            var incoming = p.settings
            if case .songMap? = modes.tempo {
                // The song map owns tempo and meter; the screen may change sounds, figures, the second track.
                incoming.bpm = settings.bpm
                incoming.numerator = settings.numerator
                incoming.denominator = settings.denominator
                incoming.accents = settings.accents
                incoming.grouping = settings.grouping
                incoming.beatRhythms = settings.beatRhythms
            }
            let tempoChanged = incoming.bpm != settings.bpm
            settings = incoming
            pending = nil
            if beat >= settings.numerator { beat = 0 }
            if tempoChanged { lastTempoChangeTime = nextBeatTime }
        }
        if beat == 0 { startBar() }
        // Случайный пропуск: the whole beat with its subdivisions is silent on every output (6.1 п. 8); beat 1 never.
        var beatMuted = false
        if case .randomMute(let p)? = modes.sound, beat > 0 { beatMuted = random.nextUnit() < p.clamped(to: 0...1) }
        // Карта песни without a loop: after the last part the clock keeps time silently until the app stops it.
        if songEnded { beatMuted = true }

        let beatStart = nextBeatTime
        let beatLength = 60 / settings.bpm * sampleRate
        // A rhythmic figure (16-16-8, clave, polyrhythm …) replaces even ticks; «Лесенка делений» overrides it.
        if modes.subdivision == nil, let rhythm = settings.rhythm(forBeat: beat) {
            scheduleFigure(rhythm, beatStart: beatStart, beatLength: beatLength, muted: beatMuted)
        } else {
            var ticks = settings.subdivision
            var displaced: ClickPattern?
            if case .displacedClick(let pattern)? = modes.sound { displaced = pattern }
            if displaced == .offbeats && ticks % 2 == 1 { ticks = ticks == 1 ? 2 : ticks + 1 }
            let tickLength = beatLength / Double(ticks)
            let swingOn = ticks % 2 == 0 && settings.swing != 0.5

            for k in 0..<ticks {
                var offset = Double(k) * tickLength
                if swingOn && k % 2 == 1 { offset = (Double(k - 1) + 2 * settings.swing) * tickLength }
                let level = k == 0 ? settings.accents[min(beat, settings.accents.count - 1)] : .soft
                var silent = barSilent || beatMuted
                if let displaced, !silent {
                    switch displaced {
                    case .backbeats: silent = !(k == 0 && beat % 2 == 1)
                    case .offbeats: silent = !(k == ticks / 2)
                    case .downbeat: silent = !(k == 0 && beat == 0)
                    }
                }
                queue.append(ClickEvent(sampleTime: Int64((beatStart + offset).rounded()), bar: bar, beat: beat, tick: k,
                                        level: level, isSilent: silent, bpm: settings.bpm, subdivision: ticks))
            }
        }
        if let poly = settings.poly { schedulePoly(poly, beatStart: beatStart, beatLength: beatLength, muted: barSilent || beatMuted) }
        totalBeats += 1
        nextBeatTime = beatStart + beatLength
        beat += 1
        if beat >= settings.numerator { beat = 0 }
    }

    /// ME-8: the second track's clicks inside this beat, merged into the queue in time order.
    private func schedulePoly(_ poly: PolyTrack, beatStart: Double, beatLength: Double, muted: Bool) {
        func add(_ offset: Double, first: Bool, index: Int) {
            queue.append(ClickEvent(sampleTime: Int64((beatStart + offset * beatLength).rounded()), bar: bar, beat: beat, tick: index,
                                    level: first ? .strong : .normal, isSilent: muted, bpm: settings.bpm, subdivision: 1, track: 1))
        }
        switch poly.kind {
        case .meter:
            if totalBeats % poly.count == 0 { add(0, first: true, index: 0) }
        case .rhythm:
            // Pulses are counted from the bar line (a whole-bar span) or from the start of the run.
            let span = poly.span ?? settings.numerator
            let position = poly.span == nil ? beat : totalBeats % span
            for j in 0..<poly.count {
                let at = Double(j) * Double(span) / Double(poly.count)
                if at >= Double(position) - 1e-9 && at < Double(position + 1) - 1e-9 { add(at - Double(position), first: j == 0, index: j) }
            }
        }
        // Insertion sort: a handful of events, no allocation on the render thread.
        if queue.count > 1 {
            for i in 1..<queue.count {
                let e = queue[i]
                var j = i - 1
                while j >= 0 && (queue[j].sampleTime > e.sampleTime || (queue[j].sampleTime == e.sampleTime && queue[j].track > e.track)) {
                    queue[j + 1] = queue[j]
                    j -= 1
                }
                queue[j + 1] = e
            }
        }
    }

    /// The clicks of a figure that fall inside this beat. A figure longer than the bar runs on across the bar line
    /// (clave 3-2 in 3/4 stays clave); the beat itself always has an event — a rest when the figure is silent there.
    private func scheduleFigure(_ rhythm: BeatRhythm, beatStart: Double, beatLength: Double, muted: Bool) {
        let beats = rhythm.beats(numerator: settings.numerator)
        let inFigure = Double((max(0, bar) * settings.numerator + beat) % beats)
        var offsets = rhythm.positions(numerator: settings.numerator)
            .filter { $0 >= inFigure - 1e-9 && $0 < inFigure + 1 - 1e-9 }
            .map { max(0, $0 - inFigure) }
        let onBeat = offsets.first.map { $0 < 1e-9 } ?? false
        if !onBeat { offsets.insert(0, at: 0) }
        let perBeat = max(1, Int(rhythm.stepsPerBeat.rounded(.up)))
        for (k, offset) in offsets.enumerated() {
            let level = k == 0 ? settings.accents[min(beat, settings.accents.count - 1)] : .soft
            let rest = k == 0 && !onBeat
            queue.append(ClickEvent(sampleTime: Int64((beatStart + offset * beatLength).rounded()), bar: bar, beat: beat, tick: k,
                                    level: level, isSilent: barSilent || muted || rest, bpm: settings.bpm, subdivision: perBeat,
                                    isRest: rest && !barSilent))
        }
    }

    private func resetModeState() {
        barSilent = false
        barsSinceTempoChange = 0
        forwardPhase = true
        targetReported = false
        ladderIndex = 0
        ladderBars = 0
        gapPosition = 0
        fastPhase = false
        totalBeats = 0
        songEnded = false
        sectionIndex = 0
        if case let .fastSlow(slow, _, _)? = modes.tempo { settings.bpm = slow.clamped(to: MeterSettings.tempoRange) }
        if case let .songMap(sections, _, countIn)? = modes.tempo, let first = sections.first {
            applySection(first)
            sectionBarsLeft = first.bars + (countIn ? 1 : 0)
        }
        if case let .gapBars(_, off, _, _)? = modes.sound { gapOff = off } else { gapOff = 0 }
        if case let .ladder(steps, _)? = modes.subdivision, let first = steps.first { settings.subdivision = first }
    }

    private func applySection(_ section: SongSection) {
        if settings.numerator != section.numerator {
            settings.grouping = nil
            settings.beatRhythms = nil
            settings.accents = MeterSettings.defaultAccents(numerator: section.numerator, grouping: nil)
        }
        settings.numerator = section.numerator
        settings.denominator = section.denominator
        settings.bpm = section.bpm
    }

    /// Карта песни at a bar boundary: the next section when this one is played out.
    private func advanceSong(_ sections: [SongSection], loop: Bool, countIn: Bool) {
        guard !sections.isEmpty, !songEnded else { return }
        if bar == 0 {
            if !countIn { notices.append(.sectionChanged(0)) }
            return
        }
        sectionBarsLeft -= 1
        if countIn && sectionIndex == 0 && sectionBarsLeft == sections[0].bars { notices.append(.sectionChanged(0)) }
        guard sectionBarsLeft <= 0 else { return }
        var next = sectionIndex + 1
        if next >= sections.count {
            guard loop else { songEnded = true; notices.append(.songEnded); return }
            next = 0
        }
        sectionIndex = next
        let section = sections[next]
        let tempoChanged = section.bpm != settings.bpm
        applySection(section)
        sectionBarsLeft = section.bars
        notices.append(.sectionChanged(next))
        if tempoChanged { notices.append(.tempoChanged(settings.bpm)) }
    }

    /// Mode logic at a bar boundary (ME-6).
    private func startBar() {
        bar += 1
        if case let .songMap(sections, loop, countIn)? = modes.tempo { advanceSong(sections, loop: loop, countIn: countIn) }
        guard bar > 0 else { applyGap(); return }

        switch modes.tempo {
        case let .speedUp(step, every, target)?:
            barsSinceTempoChange += 1
            let due: Bool
            switch every {
            case .bars(let n): due = barsSinceTempoChange >= max(1, n)
            case .seconds(let s): due = (nextBeatTime - lastTempoChangeTime) / sampleRate >= s
            }
            if due && !targetReported {
                changeTempo(by: target >= settings.bpm ? abs(step) : -abs(step), target: target)
            }
        case let .twoForwardOneBack(step, everyBars, target)?:
            barsSinceTempoChange += 1
            if barsSinceTempoChange >= max(1, everyBars) && !targetReported {
                changeTempo(by: forwardPhase ? 2 * abs(step) : -abs(step), target: target)
                forwardPhase.toggle()
            }
        case let .fastSlow(slow, fast, everyBars)?:
            barsSinceTempoChange += 1
            if barsSinceTempoChange >= max(1, everyBars) {
                fastPhase.toggle()
                settings.bpm = (fastPhase ? fast : slow).clamped(to: MeterSettings.tempoRange)
                barsSinceTempoChange = 0
                lastTempoChangeTime = nextBeatTime
                notices.append(.tempoChanged(settings.bpm))
            }
        case .songMap?:
            break
        case nil:
            break
        }

        if case let .ladder(steps, barsPerStep)? = modes.subdivision, !steps.isEmpty {
            ladderBars += 1
            if ladderBars >= max(1, barsPerStep) {
                ladderBars = 0
                ladderIndex = (ladderIndex + 1) % steps.count
                settings.subdivision = steps[ladderIndex].clamped(to: MeterSettings.subdivisionRange)
                notices.append(.subdivisionChanged(settings.subdivision))
            }
        }
        applyGap()
    }

    private func applyGap() {
        guard case let .gapBars(on, _, growth, maxOff)? = modes.sound else { barSilent = false; return }
        let wasSilent = barSilent
        let cycle = max(1, on) + gapOff
        if bar > 0 {
            gapPosition += 1
            if gapPosition >= cycle {
                gapPosition = 0
                gapOff = min(maxOff, gapOff + growth)
            }
        }
        barSilent = gapPosition >= max(1, on)
        if barSilent && !wasSilent { notices.append(.silentBarsStarted) }
        if !barSilent && wasSilent { notices.append(.silentBarsEnded) }
    }

    private func changeTempo(by delta: Double, target: Double) {
        var bpm = settings.bpm + delta
        // Do not overshoot the target when moving towards it.
        if (delta > 0 && settings.bpm < target && bpm > target) || (delta < 0 && settings.bpm > target && bpm < target) {
            bpm = target
        }
        settings.bpm = bpm
        barsSinceTempoChange = 0
        lastTempoChangeTime = nextBeatTime
        notices.append(.tempoChanged(settings.bpm))
        if settings.bpm == target && !targetReported {
            targetReported = true
            notices.append(.targetReached)
        }
    }
}

/// Small fast PRNG (SplitMix64) for the render thread.
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    /// Uniform in 0 ..< 1.
    mutating func nextUnit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
