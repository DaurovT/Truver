#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import TruverDSP
import TruverTheory

/// A rhythmic figure with everything the Flutter metronome draws and names (RhythmViews.swift, MetronomeSheets.swift):
/// the core `BeatRhythm` as stored in `MeterSettings`, its names and the notation values.
struct RhythmDTO: Encodable {
    var rhythm: BeatRhythm
    var name: String
    var shortName: String
    var spokenName: String
    var tuplet: Int?
    var tupletLabel: String?
    var durations: [Int]
    var stepsPerBeat: Double
    var isPlain: Bool

    init(_ r: BeatRhythm) {
        rhythm = r
        name = BeatRhythms.name(r)
        shortName = r.shortName
        spokenName = BeatRhythms.spokenName(r)
        tuplet = r.tuplet
        tupletLabel = r.tupletLabel
        durations = r.durations
        stepsPerBeat = r.stepsPerBeat
        isPlain = r.isPlain
    }
}

/// The app's `MetronomeModes` (Storage.swift) as the Flutter settings store it — same field names.
struct AppModesDTO: Decodable {
    var tempo: String
    var subdivision: String
    var sound: String
    var start: Double
    var target: Double
    var step: Double
    var interval: String
    var every: Int
    var everySeconds: Int
    var pattern: ClickPattern
    var gapOn: Int
    var gapOff: Int
    var ladderBarsPerStep: Int
    var fast: Double
    var fastSlowBars: Int
    var muteChance: Int
    var song: [SongSection]
    var songCountIn: Bool
    var songLoop: Bool

    /// `MetronomeController.trainingModes` (iOS).
    var trainingModes: TrainingModes {
        var result = TrainingModes()
        switch tempo {
        case "speedUp":
            let every: TempoInterval = interval == "seconds" ? .seconds(Double(everySeconds)) : .bars(self.every)
            result.tempo = .speedUp(step: step, every: every, target: target)
        case "twoForward":
            result.tempo = .twoForwardOneBack(step: step, everyBars: every, target: target)
        case "fastSlow":
            result.tempo = .fastSlow(slow: start, fast: fast, everyBars: fastSlowBars)
        case "songMap":
            result.tempo = song.isEmpty ? nil : .songMap(sections: song, loop: songLoop, countIn: songCountIn)
        default: break
        }
        if subdivision == "ladder" { result.subdivision = .ladder(steps: [1, 2, 3, 4], barsPerStep: ladderBarsPerStep) }
        switch sound {
        case "displaced": result.sound = .displacedClick(pattern)
        case "gapBars": result.sound = .gapBars(on: gapOn, off: gapOff, offGrowth: 0, maxOff: gapOff)
        case "randomMute": result.sound = .randomMute(probability: Double(muteChance) / 100)
        default: break
        }
        return result
    }
}

/// Bridge commands of the Metronome feature (Flutter: lib/features/metronome). Method names: "metronome.<name>".
extension Bridge {
    nonisolated(unsafe) private static var tapTempo = TapTempo()

    func registerMetronome() {
        /// The figure library of the «Ритм» sheet: sections in order and every figure (`BeatRhythms.all`).
        struct GroupDTO: Encodable { var id: String; var title: String }
        struct Library: Encodable { var groups: [GroupDTO]; var rhythms: [RhythmDTO] }
        register("metronome.rhythms") { _ in
            Library(groups: BeatRhythmGroup.allCases.map { GroupDTO(id: $0.rawValue, title: $0.title) },
                    rhythms: BeatRhythms.all.map(RhythmDTO.init))
        }

        /// Names and notation values of arbitrary figures (a stored one, the even subdivision `sub5`…).
        struct DescribeParams: Decodable { var rhythms: [BeatRhythm] }
        register("metronome.describe", DescribeParams.self) { p in p.rhythms.map(RhythmDTO.init) }

        /// The app's modes → the engine's `TrainingModes` JSON for `audio.startMetronome` / `audio.updateMetronome`.
        struct ModesParams: Decodable { var modes: AppModesDTO }
        register("metronome.trainingModes", ModesParams.self) { p in p.modes.trainingModes }

        /// Tap tempo (ME-2): average of the last 4–8 taps, a 2 s pause restarts. `time` in seconds.
        struct TapParams: Decodable { var time: Double }
        struct TapResult: Encodable { var bpm: Double? }
        register("metronome.tap", TapParams.self) { p in TapResult(bpm: Bridge.tapTempo.tap(at: p.time)) }

        /// Flash limiting (6.1 п. 9): the densest rule with at most 3 flashes per second.
        struct MeterParams: Decodable { var settings: MeterSettings }
        struct RuleDTO: Encodable { var kind: String; var n: Int? }
        register("metronome.flashRule", MeterParams.self) { p in
            switch FlashPolicy.rule(for: p.settings) {
            case .everyBeat: return RuleDTO(kind: "everyBeat")
            case .strongBeats: return RuleDTO(kind: "strongBeats")
            case .firstBeat: return RuleDTO(kind: "firstBeat")
            case .everyNthBar(let n): return RuleDTO(kind: "everyNthBar", n: n)
            }
        }

        /// `MeterSettings.defaultAccents` (AccentLevel raw values).
        struct AccentParams: Decodable { var numerator: Int; var grouping: [Int]? }
        register("metronome.defaultAccents", AccentParams.self) { p in
            MeterSettings.defaultAccents(numerator: max(1, p.numerator), grouping: p.grouping).map(\.rawValue)
        }

        /// SM-9: the next session starts 10 % under the ceiling.
        struct CeilingParams: Decodable { var ceiling: Double }
        register("metronome.nextSessionStart", CeilingParams.self) { p in AdaptiveTempo.nextSessionStart(ceiling: p.ceiling) }

        /// SM-4: whether a subdivision of `interval` seconds can be graded.
        struct IntervalParams: Decodable { var interval: Double }
        register("metronome.gradable", IntervalParams.self) { p in RhythmThresholds().bands(subdivision: p.interval) != nil }
    }
}
