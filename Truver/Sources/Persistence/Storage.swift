import Foundation
import SwiftData
import TruverDSP
import TruverTheory

/// The instrument with its tunings (PR-1), stored as the core's Codable value.
/// CloudKit-compatible: every property has a default, no unique constraints (PRD 4, 8).
@Model
final class StoredInstrument {
    var id: UUID = UUID()
    var payload: Data = Data()
    var updatedAt: Date = Date.now

    init(_ instrument: Instrument) {
        id = instrument.id
        update(instrument)
    }

    var instrument: Instrument? { try? JSONDecoder().decode(Instrument.self, from: payload) }

    func update(_ instrument: Instrument) {
        payload = (try? JSONEncoder().encode(instrument)) ?? Data()
        updatedAt = .now
    }
}

/// One practice session of the simple v1 journal (PL-0). Names are copied so the journal survives instrument
/// replacement (6.1 п. 19).
@Model
final class PracticeEntry {
    var start: Date = Date.now
    var seconds: Double = 0
    var instrumentName: String = ""
    var tuningName: String = ""
    var lastBPM: Double = 0
    var usedMetronome: Bool = false
    var tuned: Bool = false
    /// The slowest tempo of the session (a speed trainer goes 142 → 150) and the preset that played.
    var minBPM: Double = 0
    var presetName: String = ""

    init(start: Date, instrumentName: String, tuningName: String) {
        self.start = start
        self.instrumentName = instrumentName
        self.tuningName = tuningName
    }
}

enum AppTab: String, Codable, CaseIterable, Sendable {
    case tuner, fretboard, metronome, practice
}

enum LabelMode: String, Codable, CaseIterable, Sendable {
    case notes, degrees, intervals, fingers, none

    var title: String {
        switch self {
        case .notes: return "Ноты"
        case .degrees: return "Ступени"
        case .intervals: return "Интервалы"
        case .fingers: return "Пальцы"
        case .none: return "Без подписей"
        }
    }
}

enum NeckDisplay: String, Codable, Sendable {
    case wholeNeck, position, window
}

struct FretboardSettings: Codable, Sendable, Equatable {
    var scaleId = "major"
    var tonic = NoteName(.g)
    var layout: LayoutKind = .threeNotesPerString
    var neckView: NeckDisplay = .position
    var positionNumber = 1
    var windowStart = 0
    var windowLength = 5
    var labels: LabelMode = .notes
    var lowStringOnTop = false
    var leftHanded = false
    var allowOpenStrings = true
    var eightNotePattern: EightNotePattern = .threeThreeTwo
    var clickWithPlayback = true
    /// FB-7 edits: cells hidden from or added to the scale, "course:fret".
    var hiddenCells: [String] = []
    var addedCells: [String] = []
}

struct MetronomePreset: Codable, Sendable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var settings: MeterSettings
    var modes = MetronomeModes()

    init(id: UUID = UUID(), name: String, settings: MeterSettings, modes: MetronomeModes) {
        self.id = id
        self.name = name
        self.settings = settings
        self.modes = modes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        settings = try c.decode(MeterSettings.self, forKey: .settings)
        modes = (try? c.decodeIfPresent(MetronomeModes.self, forKey: .modes)) ?? MetronomeModes()
    }
}

/// Training modes in three groups — one per group (6.1 п. 7): tempo, subdivision, sound.
struct MetronomeModes: Codable, Sendable, Equatable {
    enum Tempo: String, Codable, Sendable, CaseIterable { case none, speedUp, twoForward, fastSlow, songMap }
    enum Subdivision: String, Codable, Sendable, CaseIterable { case none, ladder }
    enum Sound: String, Codable, Sendable, CaseIterable { case none, displaced, gapBars, randomMute }
    enum Interval: String, Codable, Sendable { case bars, seconds }

    var tempo: Tempo = .none
    var subdivision: Subdivision = .none
    var sound: Sound = .none

    // Разгон / Два вперёд, один назад
    var start: Double = 120
    var target: Double = 160
    var step: Double = 4
    var interval: Interval = .bars
    var every = 4
    var everySeconds = 30
    // Перенос щелчка
    var pattern: ClickPattern = .backbeats
    // Пропадающие такты («Тренировка пропусков»: играет 4 такта, молчит 2 — canvas «Режимы»)
    var gapOn = 4
    var gapOff = 2
    // Лесенка
    var ladderBarsPerStep = 2
    // Быстро / медленно: `start` is the slow tempo (the knob sets it while stopped), `fast` the fast one.
    var fast: Double = 160
    var fastSlowBars = 4
    // Случайный пропуск: chance in percent that a beat (not the first) drops.
    var muteChance = 30
    // Карта песни: parts in order, one-bar count-in, loop.
    var song: [SongSection] = [SongSection(name: "Вступление", bpm: 120, bars: 4), SongSection(name: "Куплет", bpm: 120, bars: 8),
                               SongSection(name: "Припев", bpm: 128, bars: 8)]
    var songCountIn = true
    var songLoop = false

    var isEmpty: Bool { tempo == .none && subdivision == .none && sound == .none }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MetronomeModes()
        tempo = (try? c.decodeIfPresent(Tempo.self, forKey: .tempo)) ?? d.tempo
        subdivision = (try? c.decodeIfPresent(Subdivision.self, forKey: .subdivision)) ?? d.subdivision
        sound = (try? c.decodeIfPresent(Sound.self, forKey: .sound)) ?? d.sound
        start = (try? c.decodeIfPresent(Double.self, forKey: .start)) ?? d.start
        target = (try? c.decodeIfPresent(Double.self, forKey: .target)) ?? d.target
        step = (try? c.decodeIfPresent(Double.self, forKey: .step)) ?? d.step
        interval = (try? c.decodeIfPresent(Interval.self, forKey: .interval)) ?? d.interval
        every = (try? c.decodeIfPresent(Int.self, forKey: .every)) ?? d.every
        everySeconds = (try? c.decodeIfPresent(Int.self, forKey: .everySeconds)) ?? d.everySeconds
        pattern = (try? c.decodeIfPresent(ClickPattern.self, forKey: .pattern)) ?? d.pattern
        gapOn = (try? c.decodeIfPresent(Int.self, forKey: .gapOn)) ?? d.gapOn
        gapOff = (try? c.decodeIfPresent(Int.self, forKey: .gapOff)) ?? d.gapOff
        ladderBarsPerStep = (try? c.decodeIfPresent(Int.self, forKey: .ladderBarsPerStep)) ?? d.ladderBarsPerStep
        fast = (try? c.decodeIfPresent(Double.self, forKey: .fast)) ?? d.fast
        fastSlowBars = (try? c.decodeIfPresent(Int.self, forKey: .fastSlowBars)) ?? d.fastSlowBars
        muteChance = (try? c.decodeIfPresent(Int.self, forKey: .muteChance)) ?? d.muteChance
        song = (try? c.decodeIfPresent([SongSection].self, forKey: .song)) ?? d.song
        songCountIn = (try? c.decodeIfPresent(Bool.self, forKey: .songCountIn)) ?? d.songCountIn
        songLoop = (try? c.decodeIfPresent(Bool.self, forKey: .songLoop)) ?? d.songLoop
    }

    /// Names for chips, toasts and preset subtitles.
    static func title(_ tempo: Tempo) -> String {
        switch tempo {
        case .none: return "Нет"
        case .speedUp: return "Разгон"
        case .twoForward: return "Два вперёд, один назад"
        case .fastSlow: return "Быстро / медленно"
        case .songMap: return "Карта песни"
        }
    }

    static func title(_ subdivision: Subdivision) -> String {
        subdivision == .ladder ? "Лесенка делений" : "Нет"
    }

    static func title(_ sound: Sound) -> String {
        switch sound {
        case .none: return "Нет"
        case .displaced: return "Перенос щелчка"
        case .gapBars: return "Пропадающие такты"
        case .randomMute: return "Случайный пропуск"
        }
    }

    /// Active mode names, tempo group first («Разгон», «Пропадающие такты»…).
    var activeTitles: [String] {
        var result: [String] = []
        if tempo != .none { result.append(Self.title(tempo)) }
        if subdivision != .none { result.append(Self.title(subdivision)) }
        if sound != .none { result.append(Self.title(sound)) }
        return result
    }
}

/// Where the beat flashes (6.1 п. 9): off, on the beat strip (default) or the whole screen.
enum FlashTarget: String, Codable, Sendable, CaseIterable { case off, strip, screen }

struct MetronomeSettingsState: Codable, Sendable, Equatable {
    var meter = MeterSettings(bpm: 100)
    var modes = MetronomeModes()
    var presets: [MetronomePreset] = []
    /// The preset whose name is on the header chip; cleared when the settings drift from it.
    var currentPresetId: UUID?
    var timerEnabled = false
    var timerMinutes = 20
    var sound: ClickSounds.Kind = .click
    var flash: FlashTarget = .strip
    /// «Громкость акцента»: the strong click over the normal one, dB (−3…+17).
    var accentDB: Double = ClickSounds.defaultAccentDB

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MetronomeSettingsState()
        meter = (try? c.decodeIfPresent(MeterSettings.self, forKey: .meter)) ?? d.meter
        modes = (try? c.decodeIfPresent(MetronomeModes.self, forKey: .modes)) ?? d.modes
        presets = (try? c.decodeIfPresent([MetronomePreset].self, forKey: .presets)) ?? d.presets
        currentPresetId = try? c.decodeIfPresent(UUID.self, forKey: .currentPresetId)
        timerEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .timerEnabled)) ?? d.timerEnabled
        timerMinutes = max(1, (try? c.decodeIfPresent(Int.self, forKey: .timerMinutes)) ?? d.timerMinutes)
        sound = (try? c.decodeIfPresent(ClickSounds.Kind.self, forKey: .sound)) ?? d.sound
        flash = (try? c.decodeIfPresent(FlashTarget.self, forKey: .flash)) ?? d.flash
        accentDB = (try? c.decodeIfPresent(Double.self, forKey: .accentDB)) ?? d.accentDB
    }

    var currentPreset: MetronomePreset? { presets.first { $0.id == currentPresetId } }
}

/// App settings (PRD 8 AppSettings), stored in UserDefaults as JSON.
struct AppSettings: Codable, Sendable, Equatable {
    var notation: NoteNotation = .international
    var defaultA4: Double = 440
    var onboarded = false
    var lastTab: AppTab = .tuner
    var tunerChromatic = false
    var vibration = false
    var fretboard = FretboardSettings()
    var metronome = MetronomeSettingsState()
    /// ME-9: manual output-latency correction in milliseconds, per output device name («AirPods Pro», «Динамик»).
    var latencyOffsets: [String: Double] = [:]
    /// TH-8: the user's own scales and chords.
    var customScales: [Scale] = []
    var customChords: [Chord] = []

    private static let key = "truver.settings.v1"

    init() {}

    /// Missing keys fall back to defaults: a new field must not reset everything the user set.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        notation = (try? c.decodeIfPresent(NoteNotation.self, forKey: .notation)) ?? d.notation
        defaultA4 = (try? c.decodeIfPresent(Double.self, forKey: .defaultA4)) ?? d.defaultA4
        onboarded = (try? c.decodeIfPresent(Bool.self, forKey: .onboarded)) ?? d.onboarded
        lastTab = (try? c.decodeIfPresent(AppTab.self, forKey: .lastTab)) ?? d.lastTab
        tunerChromatic = (try? c.decodeIfPresent(Bool.self, forKey: .tunerChromatic)) ?? d.tunerChromatic
        vibration = (try? c.decodeIfPresent(Bool.self, forKey: .vibration)) ?? d.vibration
        fretboard = (try? c.decodeIfPresent(FretboardSettings.self, forKey: .fretboard)) ?? d.fretboard
        metronome = (try? c.decodeIfPresent(MetronomeSettingsState.self, forKey: .metronome)) ?? d.metronome
        latencyOffsets = (try? c.decodeIfPresent([String: Double].self, forKey: .latencyOffsets)) ?? d.latencyOffsets
        customScales = (try? c.decodeIfPresent([Scale].self, forKey: .customScales)) ?? d.customScales
        customChords = (try? c.decodeIfPresent([Chord].self, forKey: .customChords)) ?? d.customChords
    }

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return value
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}
