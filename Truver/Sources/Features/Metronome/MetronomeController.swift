import Foundation
import Observation
import TruverAudio
import TruverDSP
#if os(iOS)
import UIKit
#endif

/// Metronome screen state (6.2.6): playback, modes, presets, timer, beat strip driven by the timeline (ME-12).
@MainActor
@Observable
final class MetronomeController {
    weak var app: AppModel?

    static let bpmRange: ClosedRange<Double> = 20...400

    private(set) var isPlaying = false { didSet { if isPlaying != oldValue { app?.system?.publish() } } }
    private(set) var currentBeat: Int?
    private(set) var currentBar = 0
    /// The beat that flashes now (6.1 п. 9); nil between flashes.
    private(set) var flashBeat: Int?
    private(set) var flashOn = false
    private(set) var silentBar = false
    private(set) var liveBPM: Double?
    private(set) var timerRemaining: TimeInterval?
    private(set) var timerExpired = false
    private(set) var targetReached = false
    /// Stopped by a call or another app (6.1 п. 6): the screen offers «Продолжить».
    private(set) var interrupted = false
    /// Where the interruption caught the metronome: «Продолжить с 150 BPM, такт 12».
    private(set) var interruptedBPM: Double?
    private(set) var interruptedBar = 1
    /// Canvas «Таймер — время вышло»: the session summary alert after the timer stops the metronome.
    private(set) var sessionEnd: SessionEnd?
    /// Tempo at the start of this session (for «темп вырос с 142 до 156»).
    private var sessionStartBPM: Double?
    /// Debug (screenshots): a beat kept lit, as on the canvas boards.
    var debugLitBeat: Int?
    /// Bars since the last tempo step — for «до 146 через 2 такта».
    private(set) var barsSinceTempoChange = 0
    /// Карта песни: the playing part, the bar inside it, the count-in bar.
    private(set) var songSection = 0
    private(set) var songBar = 0
    private(set) var songCountIn = false

    static func parts(_ n: Int) -> String { ModeParamsSheet.plural(n, "часть", "части", "частей") }
    private(set) var secondsSinceTempoChange: TimeInterval = 0
    /// Started by scale playback (6.1 п. 14), stopped together with it.
    private(set) var startedByPlayback = false
    /// Screen toast (canvas: top of the screen, over the beat strip).
    private(set) var toast: MetronomeToast?

    private var pending: [TimelineTick] = []
    private var loop: Task<Void, Never>?
    private var tap = TapTempo()
    private(set) var timerEnd: Date?
    private var stopAtNextBar = false
    private var stopAfterSong = false
    private var restarting = false
    private var lastTempoChange = Date()
    private var toastTask: Task<Void, Never>?
    private var flashTask: Task<Void, Never>?
    #if os(iOS)
    private let haptic = UIImpactFeedbackGenerator(style: .rigid)
    #endif

    // MARK: Settings

    var state: MetronomeSettingsState {
        get { app?.settings.metronome ?? MetronomeSettingsState() }
        set {
            app?.settings.metronome = newValue
            if isPlaying { app?.audio.host.updateMetronome(newValue.meter) }
        }
    }

    var meter: MeterSettings {
        get { state.meter }
        set {
            var s = state
            var m = newValue
            if m.accents.count != m.numerator { m.accents = MeterSettings.defaultAccents(numerator: m.numerator, grouping: m.grouping) }
            // Beats that no longer exist lose their own figure (it came back after 4 → 3 → 4 — UX check).
            if let own = m.beatRhythms, own.count > m.numerator {
                let kept = Array(own.prefix(m.numerator))
                m.beatRhythms = kept.allSatisfy { $0 == nil } ? nil : kept
            }
            s.meter = m
            state = s
        }
    }

    var bpm: Double {
        get { meter.bpm }
        set { var m = meter; m.bpm = newValue.rounded().clamped(to: Self.bpmRange); meter = m }
    }

    var modes: MetronomeModes {
        get { state.modes }
        set {
            var s = state
            s.modes = newValue
            state = s
            restartIfPlaying()
        }
    }

    /// The tempo shown on the knob: the live one while a mode changes it.
    /// Before the start a tempo mode shows its starting tempo (it jumped from 100 to 120 on start — iPhone UX check).
    var displayBPM: Double {
        if isPlaying { return liveBPM ?? bpm }
        if state.modes.tempo == .songMap { return state.modes.song.first?.bpm ?? bpm }
        return state.modes.tempo != .none ? state.modes.start.clamped(to: Self.bpmRange) : bpm
    }

    var trainingModes: TrainingModes {
        let m = state.modes
        var result = TrainingModes()
        switch m.tempo {
        case .none: break
        case .speedUp:
            let every: TempoInterval = m.interval == .bars ? .bars(m.every) : .seconds(Double(m.everySeconds))
            result.tempo = .speedUp(step: m.step, every: every, target: m.target)
        case .twoForward:
            result.tempo = .twoForwardOneBack(step: m.step, everyBars: m.every, target: m.target)
        case .fastSlow:
            result.tempo = .fastSlow(slow: m.start, fast: m.fast, everyBars: m.fastSlowBars)
        case .songMap:
            result.tempo = m.song.isEmpty ? nil : .songMap(sections: m.song, loop: m.songLoop, countIn: m.songCountIn)
        }
        if m.subdivision == .ladder { result.subdivision = .ladder(steps: [1, 2, 3, 4], barsPerStep: m.ladderBarsPerStep) }
        switch m.sound {
        case .none: break
        case .displaced: result.sound = .displacedClick(m.pattern)
        case .gapBars: result.sound = .gapBars(on: m.gapOn, off: m.gapOff, offGrowth: 0, maxOff: m.gapOff)
        case .randomMute: result.sound = .randomMute(probability: Double(m.muteChance) / 100)
        }
        return result
    }

    var atMaximum: Bool { displayBPM >= Self.bpmRange.upperBound }
    var atMinimum: Bool { displayBPM <= Self.bpmRange.lowerBound }

    /// Flash thinning at fast tempos (6.1 п. 9).
    var flashRule: FlashRule { FlashPolicy.rule(for: meterForFlash) }
    private var meterForFlash: MeterSettings { var m = meter; m.bpm = displayBPM; return m }

    // MARK: Status line and chips (canvas «Метроном — остановлен / играет / цель»)

    /// One grey line under the beat strip: a silent bar, the tempo limits, otherwise the mode at work
    /// («Разгон: 142 → 160 · +2 каждые 4 такта», «Разгон завершён · держим 160»).
    var statusText: String? {
        if isPlaying && silentBar {
            return state.modes.sound == .randomMute ? "Пропуск · держите темп сами" : "Тихий такт · держите темп сами"
        }
        if atMaximum { return "400 BPM — максимум" }
        if atMinimum { return "20 BPM — минимум" }
        return modeStatus
    }

    private var modeStatus: String? {
        let m = state.modes
        switch m.tempo {
        case .speedUp, .twoForward:
            if targetReached && isPlaying { return "\(m.tempo == .speedUp ? "Разгон" : "Два вперёд") завершён · держим \(Int(m.target))" }
            let every = m.tempo == .speedUp && m.interval == .seconds ? "каждые \(m.everySeconds) с" : "каждые \(m.every) \(Self.bars(m.every))"
            return "\(m.tempo == .speedUp ? "Разгон" : "Два вперёд"): \(Int(m.start)) → \(Int(m.target)) · +\(Int(m.step)) \(every)"
        case .fastSlow:
            return "Быстро / медленно: \(Int(m.start)) ↔ \(Int(m.fast)) · по \(m.fastSlowBars) \(Self.bars(m.fastSlowBars))"
        case .songMap:
            return tempoChipText
        case .none: break
        }
        switch m.sound {
        case .gapBars: return "Тренировка пропусков: играет \(m.gapOn) \(Self.bars(m.gapOn)), молчит \(m.gapOff)"
        case .randomMute: return "Случайный пропуск: \(m.muteChance) % долей молчат"
        case .displaced: return "Перенос щелчка: \(patternTitle(m.pattern))"
        case .none: break
        }
        if m.subdivision == .ladder { return "Лесенка делений: 1 → 2 → 3 → 4 · по \(m.ladderBarsPerStep) \(Self.bars(m.ladderBarsPerStep))" }
        return nil
    }

    /// The mode chip: «Режим», or the active mode («↑ Разгон»), emphasized.
    var modeChip: MetronomeChip {
        let m = state.modes
        let title: String? = switch m.tempo {
        case .speedUp: "Разгон"
        case .twoForward: "Два вперёд"
        case .fastSlow: "Быстро / медленно"
        case .songMap: "Карта песни"
        case .none: switch m.sound {
            case .gapBars: "Тренировка пропусков"
            case .randomMute: "Случайный пропуск"
            case .displaced: "Перенос щелчка"
            case .none: m.subdivision == .ladder ? "Лесенка делений" : nil
            }
        }
        guard let title else { return MetronomeChip(kind: .plain, text: "Режим", action: .modes) }
        return MetronomeChip(kind: .mode, text: title, action: .modes)
    }

    /// Chips after «♫ · Проверка · 7/8 · Режим»: the second track, the timer, flash thinning.
    var chips: [MetronomeChip] {
        var result: [MetronomeChip] = []
        if let poly = meter.poly {
            result.append(MetronomeChip(kind: .plain, text: poly.kind == .rhythm ? "Полиритм \(poly.count):\(meter.numerator)" : "Полиметр \(poly.count)/\(meter.numerator)", action: .meter))
        }
        if timerExpired {
            result.append(MetronomeChip(kind: .timer, text: "Таймер \(Self.clock(Double(state.timerMinutes) * 60)) · истёк", action: .timer))
        } else if let remaining = timerRemaining {
            result.append(MetronomeChip(kind: .timer, text: Self.clock(remaining), action: .timer))
        } else if state.timerEnabled {
            result.append(MetronomeChip(kind: .timer, text: Self.clock(Double(state.timerMinutes) * 60), action: .timer))
        }
        if isPlaying && state.flash != .off, let note = flashNote {
            result.append(MetronomeChip(kind: .warning, text: note, action: nil))
        }
        return result
    }

    /// The beat lit on the strip now.
    var litBeat: Int? {
        if let debugLitBeat { return debugLitBeat }
        return flashOn && state.flash != .off ? flashBeat : nil
    }

    /// Canvas «Прервано звонком»: «Остановлено звонком. Продолжить с 150 BPM, такт 12».
    var interruptionText: String {
        "Остановлено звонком. Продолжить с \(Int((interruptedBPM ?? bpm).rounded())) BPM, такт \(interruptedBar)"
    }

    private var flashNote: String? {
        switch flashRule {
        case .everyBeat: return nil
        case .strongBeats: return "Вспышка: только сильные доли"
        case .firstBeat: return "Вспышка: только первая доля"
        case .everyNthBar(let n): return "Вспышка: раз в \(n) \(Self.bars(n))"
        }
    }

    private var tempoChipText: String {
        let m = state.modes
        if m.tempo == .songMap {
            guard isPlaying, let part = m.song[safe: songSection] else {
                return "Карта песни · \(m.song.count) \(Self.parts(m.song.count))"
            }
            if songCountIn { return "Отсчёт · затем \(part.name)" }
            return "\(part.name) · такт \(min(part.bars, songBar + 1))/\(part.bars)"
        }
        if m.tempo == .fastSlow {
            let range = "\(Int(m.start)) ↔ \(Int(m.fast))"
            guard isPlaying else { return "Быстро / медленно · \(range)" }
            let other = Int(displayBPM.rounded()) == Int(m.start.rounded()) ? m.fast : m.start
            let left = max(1, m.fastSlowBars - barsSinceTempoChange)
            return "\(range) · \(Int(other)) через \(left) \(Self.bars(left))"
        }
        let title = m.tempo == .speedUp ? "Разгон" : "Два вперёд"
        guard isPlaying else {
            return "\(title) · \(Int(m.start)) → \(Int(m.target))"
        }
        let current = displayBPM
        let next = min(m.target, current + m.step)
        if m.tempo == .speedUp && m.interval == .seconds {
            let left = max(1, Int((Double(m.everySeconds) - secondsSinceTempoChange).rounded(.up)))
            return "\(title) · до \(Int(next)) через \(left) с"
        }
        let left = max(1, m.every - barsSinceTempoChange)
        return "\(title) · до \(Int(next)) через \(left) \(Self.bars(left))"
    }

    func patternTitle(_ pattern: ClickPattern) -> String {
        switch pattern {
        case .backbeats: return "только 2 и 4"
        case .offbeats: return "только «и»"
        case .downbeat: return "только раз"
        }
    }

    /// «Продолжить · 142 BPM · Разгон».
    var resumeTitle: String {
        var parts = ["Продолжить", "\(Int(bpm)) BPM"]
        parts += state.modes.activeTitles.prefix(1)
        return parts.joined(separator: " · ")
    }

    static func bars(_ n: Int) -> String {
        let n10 = n % 10, n100 = n % 100
        if n10 == 1 && n100 != 11 { return "такт" }
        if (2...4).contains(n10) && !(12...14).contains(n100) { return "такта" }
        return "тактов"
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: Playback

    func toggle() { isPlaying ? stop() : start() }

    func start(byPlayback: Bool = false) {
        guard let app, !isPlaying else { return }
        var settings = meter
        if state.modes.tempo != .none && !byPlayback { settings.bpm = state.modes.start.clamped(to: Self.bpmRange) }
        do {
            try app.audio.ensurePlayback()
            app.audio.host.clickSound = state.sound
            app.audio.host.accentDB = state.accentDB
            if interrupted, let resume = interruptedBPM { settings.bpm = resume }
            try app.audio.host.startMetronome(settings: settings, modes: trainingModes)
            isPlaying = true
            interrupted = false
            interruptedBPM = nil
            sessionEnd = nil
            if !byPlayback { sessionStartBPM = settings.bpm }
            timerExpired = false
            targetReached = false
            startedByPlayback = byPlayback
            liveBPM = settings.bpm
            pending = []
            stopAtNextBar = false
            stopAfterSong = false
            currentBar = 0        // the play-check panel shows «Отсчёт» in bar 0 of every start
            songSection = 0
            songBar = 0
            songCountIn = state.modes.tempo == .songMap && state.modes.songCountIn
            barsSinceTempoChange = 0
            secondsSinceTempoChange = 0
            lastTempoChange = Date()
            if state.timerEnabled && !byPlayback {
                timerEnd = Date().addingTimeInterval(Double(state.timerMinutes) * 60)
                timerRemaining = Double(state.timerMinutes) * 60
            }
            startLoop()
        } catch {
            show(MetronomeToast(icon: .warning, text: "Метроном не запустился: \(error.localizedDescription)"))
        }
    }

    func stop() {
        defer { if !restarting { app?.playCheck.metronomeStopped() } }
        app?.audio.host.stopMetronome()
        isPlaying = false
        startedByPlayback = false
        currentBeat = nil
        flashBeat = nil
        flashOn = false
        silentBar = false
        timerEnd = nil
        timerRemaining = nil
        loop?.cancel()
        loop = nil
    }

    /// 6.1 п. 6: a call stops the metronome; it waits for «Продолжить» with the same tempo and mode.
    func interrupt() {
        guard isPlaying else { return }
        let live = liveBPM
        let bar = currentBar + 1
        stop()
        interrupted = true
        interruptedBPM = live
        interruptedBar = bar
    }

    /// «Ещё 5 мин» of the session-end alert: play on with a 5-minute timer.
    func extendSession(minutes: Int = 5) {
        sessionEnd = nil
        start()
        timerEnd = Date().addingTimeInterval(Double(minutes) * 60)
        timerRemaining = Double(minutes) * 60
    }

    func dismissSessionEnd() { sessionEnd = nil }

    /// Screenshot hooks (canvas boards, 7/8 «Риф 7/8» at 142):
    /// `-metroDemo` — the meter and four presets; `-metroNoPresets`; `-metroMode speedUp|gapBars|randomMute|songMap|…`;
    /// `-metroBeat N` — beat N stays lit; `-metroPose playing|target|interrupted|timerEnd|landscape`; `-metroSwipe N` —
    /// preset row N open.
    func applyDebugArguments(_ arguments: [String]) {
        func value(_ key: String) -> String? {
            guard let i = arguments.firstIndex(of: key), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        if arguments.contains("-metroDemo") {
            var s = state
            s.meter = MeterSettings(bpm: 142, numerator: 7, denominator: 8, grouping: [2, 2, 3], subdivision: 1)
            // The canvas boards draw beats 1 and 3 strong, the rest normal.
            s.meter.accents = [.strong, .normal, .strong, .normal, .normal, .normal, .normal]
            s.modes = MetronomeModes()
            s.modes.start = 142; s.modes.target = 160; s.modes.step = 2; s.modes.every = 4
            var riff = s.modes
            riff.tempo = .speedUp
            let preset = MetronomePreset(name: "Риф 7/8", settings: s.meter, modes: riff)
            s.presets = [preset,
                         MetronomePreset(name: "Разминка", settings: MeterSettings(bpm: 90, numerator: 4, denominator: 4, subdivision: 2), modes: MetronomeModes()),
                         MetronomePreset(name: "Баллада", settings: MeterSettings(bpm: 64, numerator: 6, denominator: 8, subdivision: 1), modes: MetronomeModes()),
                         MetronomePreset(name: "Соло шестнадцатыми", settings: MeterSettings(bpm: 180, numerator: 4, denominator: 4, subdivision: 4), modes: MetronomeModes())]
            s.currentPresetId = preset.id
            s.timerEnabled = false
            s.timerMinutes = 20
            s.accentDB = ClickSounds.defaultAccentDB
            state = s
            app?.settings.vibration = true   // canvas «Звуки и выход»: «Вибрация на сильной доле» on
        }
        if arguments.contains("-metroNoPresets") {
            var s = state
            s.presets = []
            state = s
        }
        if let mode = value("-metroMode") {
            let choices: [String: ModeChoice] = ["speedUp": .speedUp, "twoForward": .twoForward, "fastSlow": .fastSlow, "songMap": .songMap,
                                                 "gapBars": .gapBars, "randomMute": .randomMute, "displaced": .displaced, "ladder": .ladder]
            if let choice = choices[mode] { choose(choice) }
        }
        if let beat = value("-metroBeat").flatMap(Int.init) { debugLitBeat = beat - 1 }
        if let row = value("-metroSwipe").flatMap(Int.init) { debugOpenPreset = state.presets[safe: row - 1]?.id }
        #if DEBUG
        if let pose = value("-metroPose") { debugPose(pose) }
        #endif
    }

    /// Debug: the preset row shown swiped open (`-metroSwipe`).
    var debugOpenPreset: UUID?

    #if DEBUG
    /// Screenshot poses of the canvas boards: «играет», «цель», «прервано звонком», «время вышло».
    func debugPose(_ pose: String) {
        switch pose {
        case "playing", "target", "landscape":
            isPlaying = true
            liveBPM = pose == "target" ? state.modes.target : (pose == "landscape" ? 150 : displayBPM)
            targetReached = pose == "target"
            if pose == "target" { show(MetronomeToast(icon: .check, text: "Цель \(Int(state.modes.target)) достигнута — держим темп"), seconds: 3600) }
        case "interrupted":
            interrupted = true
            interruptedBPM = 150
            interruptedBar = 12
        case "timerEnd":
            sessionEnd = SessionEnd(minutes: 20, name: state.currentPreset?.name, startBPM: 142, endBPM: 156)
        default: break
        }
    }
    #endif

    func restartIfPlaying() {
        guard isPlaying else { return }
        let byPlayback = startedByPlayback
        restarting = true      // a settings change is not the end of a «Проверка игры» attempt
        stop()
        restarting = false
        start(byPlayback: byPlayback)
    }

    func step(_ delta: Double) {
        let value = (displayBPM + delta).clamped(to: Self.bpmRange)
        if !isPlaying && state.modes.tempo == .songMap, !state.modes.song.isEmpty {
            var s = state
            s.modes.song[0].bpm = value   // the knob sets the first part's tempo, which is what is shown
            state = s
            return
        }
        if !isPlaying && state.modes.tempo != .none {
            // Stopped with a tempo mode: the knob and ± set the mode's starting tempo, which is what is shown.
            var s = state
            s.modes.start = value
            state = s
            return
        }
        bpm = value
        liveBPM = bpm
    }

    /// The figure shown on the metronome screen: the chosen one, or the even subdivision as a figure.
    var currentRhythm: BeatRhythm {
        if let r = meter.rhythm { return r }
        let n = meter.subdivision
        return BeatRhythms.all.first { $0.span == 1 && $0.isPlain && $0.grid == n }
            ?? BeatRhythm(id: "sub\(n)", grid: n, onsets: Array(0..<n))
    }

    /// A beat's own figure (Soundbrenner-style: tap a beat); nil — back to the common one.
    func setRhythm(_ r: BeatRhythm?, beat: Int) {
        var m = meter
        var own = m.beatRhythms ?? []
        if own.count < m.numerator { own += Array(repeating: nil, count: m.numerator - own.count) }
        guard beat < own.count else { return }
        own[beat] = r.flatMap { $0.span == 1 ? $0 : nil }
        m.beatRhythms = own.allSatisfy { $0 == nil } ? nil : own
        meter = m
    }

    func beatRhythm(_ beat: Int) -> BeatRhythm? {
        guard let own = meter.beatRhythms, beat < own.count else { return nil }
        return own[beat]
    }

    /// The ladder's current step while «Лесенка делений» plays.
    private(set) var ladderSubdivision: Int?

    var ladderRhythm: BeatRhythm? {
        guard state.modes.subdivision == .ladder else { return nil }
        let n = isPlaying ? (ladderSubdivision ?? 1) : 1
        return BeatRhythms.all.first { $0.span == 1 && $0.isPlain && $0.grid == n } ?? BeatRhythm(id: "sub\(n)", grid: n, onsets: Array(0..<n))
    }

    func clearBeatRhythms() {
        var m = meter
        m.beatRhythms = nil
        meter = m
    }

    /// Quick note value (Soundbrenner-style grid): even values set the subdivision, figures set the rhythm.
    func setRhythm(_ r: BeatRhythm) {
        var m = meter
        if r.span == 1 && r.isPlain {
            m.rhythm = nil
            m.subdivision = r.grid
        } else {
            m.rhythm = r
            m.subdivision = r.span == 1 ? r.grid : 1
        }
        if !m.isSwingAvailable { m.swing = 0.5 }
        meter = m
    }

    func tapTempo() {
        if let value = tap.tap(at: Date().timeIntervalSinceReferenceDate) { bpm = value; liveBPM = bpm }
    }

    /// Accent cycle on a beat (ME-3): strong → normal → soft → off.
    func cycleAccent(_ beat: Int) {
        var m = meter
        guard m.accents.indices.contains(beat) else { return }
        m.accents[beat] = m.accents[beat].next
        meter = m
    }

    func setAccent(_ beat: Int, _ level: AccentLevel) {
        var m = meter
        guard m.accents.indices.contains(beat) else { return }
        m.accents[beat] = level
        meter = m
    }

    // MARK: Presets

    func savePreset(named name: String) {
        var s = state
        let preset = MetronomePreset(name: name, settings: s.meter, modes: s.modes)
        s.presets.append(preset)
        s.currentPresetId = preset.id
        state = s
    }

    /// Loading while playing applies from the next bar (6.2.6).
    func load(_ preset: MetronomePreset) {
        var s = state
        s.meter = preset.settings
        s.modes = preset.modes
        s.currentPresetId = preset.id
        app?.settings.metronome = s
        if isPlaying { app?.audio.host.updateMetronome(preset.settings, at: .nextBar) }
    }

    func renamePreset(_ id: UUID, to name: String) {
        var s = state
        guard let i = s.presets.firstIndex(where: { $0.id == id }), !name.isEmpty else { return }
        s.presets[i].name = name
        state = s
    }

    func deletePreset(_ id: UUID) {
        var s = state
        s.presets.removeAll { $0.id == id }
        if s.currentPresetId == id { s.currentPresetId = nil }
        state = s
    }

    /// «7/8 · 2+2+3 · Разгон», «4/4 · восьмые», «6/8», «4/4 · 16-е».
    func presetSubtitle(_ preset: MetronomePreset) -> String {
        let m = preset.settings
        var parts = ["\(m.numerator)/\(m.denominator)"]
        if let grouping = m.grouping, grouping.count > 1, grouping.reduce(0, +) == m.numerator {
            parts.append(grouping.map(String.init).joined(separator: "+"))
        }
        // The figure, not a plain value (16-16-8 or triplets on a beat were shown as plain sixteenths).
        if let figure = m.rhythm, !figure.isPlain {
            parts.append(BeatRhythms.name(figure))
        } else if let value = Self.subdivisionName(m) {
            parts.append(value)
        }
        if m.beatRhythms != nil { parts.append("свои доли") }
        parts += preset.modes.activeTitles.prefix(1)
        return parts.joined(separator: " · ")
    }

    /// The even subdivision in words: «восьмые», «16-е», «триоли»; nil without one.
    static func subdivisionName(_ m: MeterSettings) -> String? {
        let n = m.subdivision
        guard n > 1 else { return nil }
        switch n {
        case 3: return "триоли"
        case 5: return "квинтоли"
        case 6: return "секстоли"
        case 7: return "септоли"
        case 9: return "по 9"
        default:
            let value = m.denominator * n
            return value == 8 ? "восьмые" : "\(value)-е"
        }
    }

    /// Deleted presets come back with «Отменить» for 5 s (canvas «Пресеты — свайп»).
    private(set) var deletedPreset: (preset: MetronomePreset, index: Int, wasCurrent: Bool)?
    private var undoTask: Task<Void, Never>?

    func deletePresetUndoable(_ id: UUID) {
        let s = state
        guard let i = s.presets.firstIndex(where: { $0.id == id }) else { return }
        deletedPreset = (s.presets[i], i, s.currentPresetId == id)
        deletePreset(id)
        undoTask?.cancel()
        undoTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.deletedPreset = nil
        }
    }

    func undoDelete() {
        guard let d = deletedPreset else { return }
        var s = state
        s.presets.insert(d.preset, at: min(d.index, s.presets.count))
        if d.wasCurrent { s.currentPresetId = d.preset.id }
        state = s
        deletedPreset = nil
        undoTask?.cancel()
    }

    // MARK: Modes (canvas «Режимы»: one mode at a time)

    enum ModeChoice: Hashable { case normal, speedUp, twoForward, fastSlow, songMap, gapBars, randomMute, displaced, ladder }

    var modeChoice: ModeChoice {
        let m = state.modes
        switch m.tempo {
        case .speedUp: return .speedUp
        case .twoForward: return .twoForward
        case .fastSlow: return .fastSlow
        case .songMap: return .songMap
        case .none: break
        }
        switch m.sound {
        case .gapBars: return .gapBars
        case .randomMute: return .randomMute
        case .displaced: return .displaced
        case .none: break
        }
        return m.subdivision == .ladder ? .ladder : .normal
    }

    /// Chooses one mode and switches the others off.
    func choose(_ choice: ModeChoice) {
        var m = modes
        m.tempo = .none
        m.sound = .none
        m.subdivision = .none
        switch choice {
        case .normal: break
        case .speedUp: m.tempo = .speedUp
        case .twoForward: m.tempo = .twoForward
        case .fastSlow: m.tempo = .fastSlow
        case .songMap: m.tempo = .songMap
        case .gapBars: m.sound = .gapBars
        case .randomMute: m.sound = .randomMute
        case .displaced: m.sound = .displaced
        case .ladder: m.subdivision = .ladder
        }
        modes = m
    }

    // MARK: Toast

    func show(_ toast: MetronomeToast, seconds: Double = 3.4) {
        self.toast = toast
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    // MARK: Timeline

    private func startLoop() {
        loop?.cancel()
        loop = Task { [weak self] in
            var lastActivity = Date()
            while !Task.isCancelled {
                self?.poll()
                if Date().timeIntervalSince(lastActivity) >= 1 {
                    lastActivity = Date()
                    self?.app?.practice.activity(tuned: false, bpm: self?.liveBPM)
                }
                try? await Task.sleep(for: .milliseconds(8))
            }
        }
    }

    private func poll() {
        guard let app else { return }
        pending += app.audio.host.drainTimeline()
        let now = mach_absolute_time()
        let settings = meterForFlash
        let rule = FlashPolicy.rule(for: settings)   // ≤ 3 flashes/s on the strip and on the full screen (6.1 п. 9)
        while let tick = pending.first, tick.hostTime <= now {
            pending.removeFirst()
            let event = tick.event
            if event.track == 0 { app.playCheck.expect(tick) }   // SM-2: every main-track tick is an expected note
            guard event.tick == 0, event.track == 0 else { continue }   // the ME-8 second track neither flashes nor counts
            if stopAfterSong && event.beat == 0 {
                stop()
                return
            }
            if stopAtNextBar && event.beat == 0 {
                let end = liveBPM ?? bpm
                stop()
                timerExpired = true
                sessionEnd = SessionEnd(minutes: state.timerMinutes, name: state.currentPreset?.name,
                                        startBPM: sessionStartBPM ?? end, endBPM: end)
                return
            }
            if event.beat == 0 && event.bar != currentBar { barsSinceTempoChange += 1; songBar += 1 }
            currentBeat = event.beat
            currentBar = event.bar
            // A rest of the rhythmic figure is not a silent bar (the screen said «Тихий такт» on off-beat figures).
            silentBar = event.isSilent && !event.isRest
            liveBPM = event.bpm
            if state.flash != .off && FlashPolicy.flashes(event, rule: rule, accents: settings.accents) {
                flash(event.beat)
            }
            #if os(iOS)
            // «Вибрация на сильной доле».
            if app.settings.vibration && !event.isSilent && event.level == .strong {
                haptic.impactOccurred(intensity: 1)
            }
            #endif
        }
        app.playCheck.update()
        secondsSinceTempoChange = Date().timeIntervalSince(lastTempoChange)
        for notice in app.audio.host.drainNotices() {
            switch notice {
            case .tempoChanged(let value):
                liveBPM = value
                barsSinceTempoChange = 0
                lastTempoChange = Date()
            case .targetReached:
                targetReached = true
                try? app.audio.host.playEvent(.targetReached)   // SND-3
                show(MetronomeToast(icon: .check, text: "Цель \(Int(state.modes.target)) достигнута — держим темп"))
            case .subdivisionChanged(let n):
                ladderSubdivision = n
            case .silentBarsStarted, .silentBarsEnded:
                break
            case .sectionChanged(let index):
                songSection = index
                songBar = -1   // the downbeat that follows is bar 1 of the part
                songCountIn = false
                if let part = state.modes.song[safe: index] {
                    show(MetronomeToast(icon: .music, text: "\(part.name) · \(Int(part.bpm)) · \(part.numerator)/\(part.denominator)"))
                }
            case .songEnded:
                stopAfterSong = true
                show(MetronomeToast(icon: .check, text: "Песня сыграна"))
            }
        }
        if let end = timerEnd {
            let remaining = end.timeIntervalSinceNow
            timerRemaining = max(0, remaining)
            // 6.1 п. 10: the timer expires — the metronome finishes the bar and stops.
            if remaining <= 0 && !stopAtNextBar {
                stopAtNextBar = true
                try? app.audio.host.playEvent(.timerEnded)   // SND-3
            }
        }
    }

    /// Flash: lit at once, fades out (canvas `beatseq`: on for 10 %, gone by 22 % of the beat).
    private func flash(_ beat: Int) {
        flashBeat = beat
        flashOn = true
        flashTask?.cancel()
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            self?.flashOn = false
        }
    }
}

struct MetronomeToast: Equatable {
    var icon: AppIcon
    var text: String
}

/// «Занятие закончено»: «20 минут · Риф 7/8 · темп вырос с 142 до 156. Записали в «Занятия».»
struct SessionEnd: Equatable {
    var minutes: Int
    var name: String?
    var startBPM: Double
    var endBPM: Double

    var message: String {
        var parts = ["\(minutes) \(ModeParamsSheet.minutes(minutes))"]
        if let name { parts.append(name) }
        let a = Int(startBPM.rounded()), b = Int(endBPM.rounded())
        parts.append(a == b ? "темп \(b)" : (b > a ? "темп вырос с \(a) до \(b)" : "темп с \(a) до \(b)"))
        return parts.joined(separator: " · ") + ". Записали в «Занятия»."
    }
}

struct MetronomeChip: Identifiable, Equatable {
    enum Kind { case plain, mode, target, timer, warning }
    enum Action { case modes, timer, meter }
    var kind: Kind
    var text: String
    var action: Action?
    var id: String { text }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
