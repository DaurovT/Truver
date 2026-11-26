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
import TruverDSP
import TruverHost
import TruverTheory

// MARK: DTOs — what the Flutter side reads every frame

struct PitchDTO: Encodable {
    /// Cents from A4 = 440 (the core's pitch space).
    var cents: Double
    /// «A2», «F♯1», «соль♯2» — with the tuning's accidental family and the app's notation.
    var label: String
    /// Without octave: «A», «F♯», «соль♯».
    var name: String
    var octave: Int
}

struct StringRefDTO: Codable, Hashable {
    var course: Int
    var string: Int
}

struct TargetDTO: Encodable {
    /// "string" (a string of the tuning) or "chromatic" (nearest note).
    var kind: String
    var string: StringRefDTO?
    var target: PitchDTO
    /// played − target; negative: flat, tighten.
    var deviation: Double
    /// Chromatic mode: the nearest string within ±300 cents.
    var hintString: StringRefDTO?
    var hintTarget: PitchDTO?
    var hintDeviation: Double?
}

struct ReadingDTO: Encodable {
    var frequency: Double
    var pitch: PitchDTO
    var target: TargetDTO
    var provisional: Bool
    var inTune: Bool
}

struct StrobeDTO: Encodable {
    var cents: Double
    var angle: Double
    var stable: Bool
    var harmonic: Int
}

struct TunerUpdateDTO: Encodable {
    var time: Double
    /// "idle", "listening", "outOfRange", "reading".
    var display: String
    var reading: ReadingDTO?
    var level: Double
    var strobe: StrobeDTO?
    /// Strings that just reached ±3 c for 0.3 s (TU-8).
    var tuned: [StringRefDTO]
    var allTuned: Bool
}

struct TickDTO: Encodable {
    var hostNanos: Int64
    var bar: Int
    var beat: Int
    var tick: Int
    /// AccentLevel raw value.
    var level: Int
    var silent: Bool
    var rest: Bool
    var bpm: Double
    var subdivision: Int
    var track: Int
}

struct NoticeDTO: Encodable {
    /// tempoChanged, targetReached, subdivisionChanged, silentBarsStarted, silentBarsEnded, sectionChanged, songEnded.
    var kind: String
    var value: Double?
}

struct PollDTO: Encodable {
    var now: Int64
    var tuner: [TunerUpdateDTO]
    var ticks: [TickDTO]
    var notices: [NoticeDTO]
    var metronomeRunning: Bool
    var tunerRunning: Bool
}

extension Bridge {
    func pitchDTO(_ pitch: Pitch, spelledAs course: Int? = nil) -> PitchDTO {
        let name: NoteName
        if let course, let main = tuning.spelledNotes[safe: course] {
            name = main.name
        } else {
            let flats = tuning.spelledNotes.contains { $0.name.accidental < 0 }
            name = NoteName.simpleSpelling(ofPitchClass: pitch.pitchClass, preferFlats: flats)
        }
        let note = SpelledNote(name, midi: pitch.nearestMIDI)
        return PitchDTO(cents: pitch.cents, label: formatter.string(note), name: formatter.string(note.name), octave: note.octave)
    }

    func dto(_ update: TunerUpdate) -> TunerUpdateDTO {
        var result = TunerUpdateDTO(time: update.time, display: "idle", reading: nil, level: update.levelDB,
                                    strobe: update.strobe.map { StrobeDTO(cents: $0.cents, angle: $0.angle, stable: $0.isStable, harmonic: $0.harmonic) },
                                    tuned: [], allTuned: false)
        switch update.display {
        case .idle: result.display = "idle"
        case .listening: result.display = "listening"
        case .outOfRange: result.display = "outOfRange"
        case .reading(let r):
            result.display = "reading"
            let target: TargetDTO
            switch r.target {
            case let .string(ref, pitch, deviation):
                target = TargetDTO(kind: "string", string: StringRefDTO(course: ref.course, string: ref.string),
                                   target: pitchDTO(pitch, spelledAs: ref.course), deviation: deviation)
            case let .chromatic(nearest, deviation, hint):
                target = TargetDTO(kind: "chromatic", string: nil, target: pitchDTO(nearest), deviation: deviation,
                                   hintString: hint.map { StringRefDTO(course: $0.string.course, string: $0.string.string) },
                                   hintTarget: hint.map { pitchDTO($0.target, spelledAs: $0.string.course) },
                                   hintDeviation: hint?.deviationCents)
            }
            result.reading = ReadingDTO(frequency: r.frequency, pitch: pitchDTO(r.pitch), target: target,
                                        provisional: r.isProvisional, inTune: r.isInTune)
        }
        for event in update.events {
            switch event {
            case .stringTuned(let ref): result.tuned.append(StringRefDTO(course: ref.course, string: ref.string))
            case .allStringsTuned: result.allTuned = true
            }
        }
        return result
    }

    static func dto(_ notice: MetronomeNotice) -> NoticeDTO {
        switch notice {
        case .tempoChanged(let bpm): NoticeDTO(kind: "tempoChanged", value: bpm)
        case .targetReached: NoticeDTO(kind: "targetReached")
        case .subdivisionChanged(let n): NoticeDTO(kind: "subdivisionChanged", value: Double(n))
        case .silentBarsStarted: NoticeDTO(kind: "silentBarsStarted")
        case .silentBarsEnded: NoticeDTO(kind: "silentBarsEnded")
        case .sectionChanged(let i): NoticeDTO(kind: "sectionChanged", value: Double(i))
        case .songEnded: NoticeDTO(kind: "songEnded")
        }
    }

    func registerAudio() {
        struct TunerParams: Decodable {
            /// "auto", "chromatic" or "manual" (+ course, string).
            var mode: String
            var course: Int?
            var string: Int?
            var noiseGate: Double?
            var strobe: Bool?
            var channel: Int?
        }
        register("audio.startTuner", TunerParams.self) { [unowned self] p in
            let audio = try requireAudio()
            var config = TunerConfiguration(sampleRate: 48_000)
            config.a4 = a4
            if let gate = p.noiseGate { config.noiseGateDB = gate }
            config.strobe = p.strobe ?? false
            let mode: TunerMode
            switch p.mode {
            case "chromatic": mode = .chromatic
            case "manual": mode = .manual(course: p.course ?? 0, string: p.string ?? 0)
            default: mode = .auto
            }
            try audio.startTuner(configuration: config, tuning: tuning, mode: mode, channel: p.channel ?? 0)
            return ["sampleRate": audio.inputSampleRate]
        }
        register("audio.stopTuner") { [unowned self] _ in
            audio?.stopTuner()
            return Done()
        }
        struct PauseParams: Decodable { var seconds: Double }
        register("audio.pauseAnalysis", PauseParams.self) { [unowned self] p in
            audio?.pauseAnalysis(seconds: p.seconds)
            return Done()
        }

        register("audio.poll") { [unowned self] _ in
            guard let audio else {
                return PollDTO(now: HostClock.nowNanos(), tuner: [], ticks: [], notices: [], metronomeRunning: false, tunerRunning: false)
            }
            let ticks = audio.drainTimeline().map { t in
                TickDTO(hostNanos: t.hostNanos, bar: t.event.bar, beat: t.event.beat, tick: t.event.tick,
                        level: t.event.level.rawValue, silent: t.event.isSilent, rest: t.event.isRest,
                        bpm: t.event.bpm, subdivision: t.event.subdivision, track: t.event.track)
            }
            return PollDTO(now: HostClock.nowNanos(), tuner: audio.drainTunerUpdates().map(dto), ticks: ticks,
                           notices: audio.drainNotices().map(Self.dto), metronomeRunning: audio.isMetronomeRunning,
                           tunerRunning: audio.isTunerRunning)
        }

        struct MetronomeParams: Decodable {
            var settings: MeterSettings
            var modes: TrainingModes?
            /// "nextBeat" (default) or "nextBar" (presets).
            var at: String?
        }
        register("audio.startMetronome", MetronomeParams.self) { [unowned self] p in
            try requireAudio().startMetronome(settings: p.settings, modes: p.modes ?? .none)
            return Done()
        }
        register("audio.updateMetronome", MetronomeParams.self) { [unowned self] p in
            let audio = try requireAudio()
            audio.updateMetronome(p.settings, at: p.at == "nextBar" ? .nextBar : .nextBeat)
            if let modes = p.modes { audio.setModes(modes) }
            return Done()
        }
        register("audio.stopMetronome") { [unowned self] _ in
            audio?.stopMetronome()
            return Done()
        }

        struct NoteParams: Decodable {
            struct Note: Decodable {
                /// Cents from A4 = 440, or a frequency.
                var cents: Double?
                var frequency: Double?
                var offset: Double?
                var string: Int?
            }
            var notes: [Note]
            /// "pluck" (default) or "reference" (+ duration).
            var kind: String?
            var duration: Double?
            var velocity: Double?
            /// "now" (default, + delay), "nextBar" (+ delay as fallback) or "sample" (+ sample).
            var start: String?
            var delay: Double?
            var sample: Int64?
            var noteDuration: Double?
        }
        register("audio.playNotes", NoteParams.self) { [unowned self] p in
            let audio = try requireAudio()
            let a4 = self.a4
            let notes = p.notes.map { n -> (frequency: Double, offset: Double) in
                (n.frequency ?? Pitch(cents: n.cents ?? 0).frequency(a4: a4), n.offset ?? 0)
            }
            let strings = p.notes.contains { $0.string != nil } ? p.notes.map { $0.string ?? 0 } : nil
            let kind: NoteSynth.Kind = p.kind == "reference" ? .reference(duration: p.duration ?? 3) : .pluck
            let start: AudioHost.NoteStart
            switch p.start {
            case "nextBar": start = .nextBar(fallbackDelay: p.delay ?? 0.03)
            case "sample": start = .sample(p.sample ?? 0)
            default: start = .now(delay: p.delay ?? 0.03)
            }
            let lead = try audio.playNotes(notes, start: start, kind: kind, velocity: p.velocity ?? 0.8,
                                           strings: strings, noteDuration: p.noteDuration)
            return ["lead": lead, "startSample": Double(audio.lastNotesStartSample), "sampleRate": audio.noteSampleRate]
        }
        register("audio.stopNotes") { [unowned self] _ in
            audio?.stopNotes()
            return Done()
        }

        struct DroneParams: Decodable { var cents: Double? }
        register("audio.drone", DroneParams.self) { [unowned self] p in
            let audio = try requireAudio()
            if let cents = p.cents { try audio.startDrone(frequency: Pitch(cents: cents).frequency(a4: a4)) } else { audio.stopDrone() }
            return Done()
        }
        struct EventParams: Decodable { var sound: EventSound }
        register("audio.event", EventParams.self) { [unowned self] p in
            try requireAudio().playEvent(p.sound)
            return Done()
        }
        struct VolumeParams: Decodable {
            var click: Float
            var notes: Float
            var reference: Float
            var clickSound: String?
            var latencyOffset: Double?
            var accentDB: Double?
        }
        register("audio.setVolumes", VolumeParams.self) { [unowned self] p in
            let audio = try requireAudio()
            audio.setVolumes(click: p.click, notes: p.notes, reference: p.reference)
            if let raw = p.clickSound, let kind = ClickSounds.Kind(rawValue: raw) { audio.clickSound = kind }
            if let offset = p.latencyOffset { audio.latencyOffset = offset }
            if let db = p.accentDB { audio.accentDB = db }
            return Done()
        }
        register("audio.diagnostics") { [unowned self] _ in audio?.diagnostics ?? [:] }
    }
}
