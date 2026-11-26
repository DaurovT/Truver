import Foundation
#if os(iOS)
import AVFoundation
#endif
import Observation
import SwiftData
import SwiftUI
import TruverDSP
import TruverTheory

/// Root state: settings, the instrument with its tunings, audio and the feature controllers.
@MainActor
@Observable
final class AppModel {
    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            if settings.metronome != oldValue.metronome { schedulePublish() }
            if settings.latencyOffsets != oldValue.latencyOffsets { audio.latencyOffsets = settings.latencyOffsets }
            if settings.customScales != oldValue.customScales || settings.customChords != oldValue.customChords {
                UserLibrary.shared.set(scales: settings.customScales, chords: settings.customChords)
            }
        }
    }
    private(set) var instrument: Instrument
    var showOnboarding: Bool
    var showSettings = false
    /// FB-12 «Тренажёр грифа» (full screen from «Занятия»).
    let trainer = FretTrainerController()
    /// Stage SM «Проверка игры» on the metronome.
    let playCheck = PlayCheckController()
    /// PL-1, PL-2 «Занятие».
    let session = PracticeSessionController()
    var showSession = false
    var showTrainer = false
    #if os(iOS)
    /// Live Activity of the metronome (6.2.9).
    private var metronomeActivity: MetronomeActivityController?
    #endif
    /// SYS-1…5: Siri, Shortcuts, the Action button, Control Center and widgets.
    private(set) var system: SystemIntegration?
    private var publishTask: Task<Void, Never>?

    /// Widgets and controls follow the app half a second after the last change (the knob turns many times a second).
    func schedulePublish() {
        #if os(iOS)
        publishTask?.cancel()
        publishTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.system?.publish()
        }
        #endif
    }
    /// Canvas-style sheet over the whole app (dim + panel), see `SheetHost`.
    var sheet: AppSheet?
    /// «Копией текущего»: the copy lives here until «Сохранить» — closing the editor leaves no trace (iPhone UX check).
    var unsavedTuning: Tuning?
    /// The tuning editor was opened from the tuner's pro panel: closing it returns to the tuner, not to the list.
    var tuningEditorFromTuner = false
    var showTunings = false
    var notice: String?
    /// Icon of the current notice (canvas toasts: lock, Bluetooth, warning); nil = the plain capsule.
    var noticeIcon: AppIcon?
    var noticeIconColor: Color = Theme.textSecondary

    let audio = AudioServices()
    let tuner: TunerController
    let metronome: MetronomeController
    let fretboard: FretboardController
    let practice: PracticeTracker

    private let context: ModelContext
    private var stored: StoredInstrument

    init(context: ModelContext) {
        self.context = context
        let arguments = ProcessInfo.processInfo.arguments
        var settings = AppSettings.load()
        if arguments.contains("-resetSettings") { settings = AppSettings() }
        if arguments.contains("-skipOnboarding") { settings.onboarded = true }
        if let i = arguments.firstIndex(of: "-tab"), i + 1 < arguments.count, let tab = AppTab(rawValue: arguments[i + 1]) {
            settings.lastTab = tab
        }
        self.settings = settings
        showOnboarding = !settings.onboarded
        audio.latencyOffsets = settings.latencyOffsets
        UserLibrary.shared.set(scales: settings.customScales, chords: settings.customChords)

        let existing = (try? context.fetch(FetchDescriptor<StoredInstrument>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])))?.first
        if let existing, let instrument = existing.instrument {
            self.stored = existing
            self.instrument = instrument
        } else {
            let instrument = TuningTemplates.template(id: "g6-standard-e")!.makeInstrument()
            let record = StoredInstrument(instrument)
            context.insert(record)
            self.stored = record
            self.instrument = instrument
        }

        tuner = TunerController()
        metronome = MetronomeController()
        fretboard = FretboardController()
        practice = PracticeTracker(context: context)
        tuner.app = self
        metronome.app = self
        fretboard.app = self
        practice.app = self
        trainer.app = self
        playCheck.app = self
        session.app = self
        audio.onConfigurationChange = { [weak self] in self?.tuner.handleAudioRestart() }
        #if os(iOS)
        // 6.1 п. 6: an interruption stops the metronome, which waits for "Старт"; the tuner resumes by itself.
        audio.session.onInterruption = { [weak self] began, _ in
            guard let self else { return }
            if began {
                // Canvas «Метроном — после прерывания»: «Остановлен из-за звонка» + «Продолжить».
                if self.metronome.isPlaying { self.metronome.interrupt() }
                self.fretboard.stopPlayback()
            } else {
                self.tuner.handleAudioRestart()
            }
        }
        // AU-7: the input disappeared or came back.
        audio.session.onRouteChange = { [weak self] reason in
            guard let self else { return }
            self.audio.applyLatency()   // ME-9: the correction belongs to the output that is playing now
            let route = AVAudioSession.sharedInstance().currentRoute
            let builtIn = route.inputs.allSatisfy { $0.portType == .builtInMic }
            let bluetooth = route.outputs.contains { [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE].contains($0.portType) }
            // Canvas «Тюнер — Bluetooth / интерфейс отключён / вход переключён»: notices over the tuner (TunerController).
            switch reason {
            case .oldDeviceUnavailable:
                if builtIn { self.tuner.routeChanged(disconnected: true, bluetoothOutput: nil, latency: 0, input: nil) }
            case .newDeviceAvailable:
                if bluetooth && builtIn {
                    let output = route.outputs.first { [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE].contains($0.portType) }?.portName
                    self.tuner.routeChanged(disconnected: false, bluetoothOutput: output ?? "Bluetooth",
                                            latency: AVAudioSession.sharedInstance().outputLatency, input: nil)
                } else if let input = route.inputs.first, !builtIn {
                    self.tuner.routeChanged(disconnected: false, bluetoothOutput: nil, latency: 0, input: input.portName)
                }
            default: break
            }
        }
        #endif
        // Screenshot / test hook: start with a given template.
        if let i = arguments.firstIndex(of: "-template"), i + 1 < arguments.count,
           let template = TuningTemplates.template(id: arguments[i + 1]) {
            replaceInstrument(with: template)
        }
        fretboard.recompute()
        #if os(iOS)
        metronomeActivity = MetronomeActivityController(app: self)
        system = SystemIntegration(app: self)
        system?.publish()
        #endif
        // SND-7 volumes (settings «Громкость»).
        let d = UserDefaults.standard
        audio.host.setVolumes(click: Float(d.object(forKey: "vol.click") as? Double ?? 0.8),
                              notes: Float(d.object(forKey: "vol.notes") as? Double ?? 0.6),
                              reference: Float(d.object(forKey: "vol.reference") as? Double ?? 0.5))
        #if DEBUG && targetEnvironment(simulator)
        // UI tests in the simulator stay silent: its sound goes through the Mac's speakers.
        if arguments.contains("-muteAudio") { audio.host.setVolumes(click: 0, notes: 0, reference: 0) }
        #endif
        // Screenshot hooks of the metronome boards: `-metroDemo`, `-metroMode`, `-metroBeat`, `-metroPose`… (MetronomeController).
        metronome.applyDebugArguments(arguments)
        if arguments.contains("-resetFretboard") {
            self.settings.fretboard = FretboardSettings()
            fretboard.recompute()
        }
        if arguments.contains("-fretDemo") {
            var f = self.settings.fretboard
            f.scaleId = "phrygian-dominant"
            f.tonic = NoteName(.e)
            f.neckView = .position
            f.positionNumber = 2
            f.labels = .degrees
            self.settings.fretboard = f
            fretboard.recompute()
        }
        if let i = arguments.firstIndex(of: "-notation"), i + 1 < arguments.count, let n = NoteNotation(rawValue: arguments[i + 1]) {
            self.settings.notation = n
        }
        if let i = arguments.firstIndex(of: "-capo"), i + 1 < arguments.count, let capo = Int(arguments[i + 1]) {
            updateInstrument { $0.capo = capo }
        }
        if arguments.contains("-neckWhole") || arguments.contains("-lowTop") {
            var f = self.settings.fretboard
            if arguments.contains("-neckWhole") { f.neckView = .wholeNeck }
            if arguments.contains("-lowTop") { f.lowStringOnTop = true }
            self.settings.fretboard = f
            fretboard.recompute()
        }
        // Screenshot hook: `-fan` — the first typical fan of this instrument (PR-7).
        if arguments.contains("-fan") {
            updateInstrument { inst in
                inst.multiscale = InstrumentStringsSheet.fanPresets(for: inst).first?.1
                InstrumentStringsSheet.syncStrings(&inst)
            }
        }
        if let i = arguments.firstIndex(of: "-fretMode"), i + 1 < arguments.count {
            switch arguments[i + 1] {
            case "chord":
                fretboard.mode = .chord; fretboard.chordRoot = NoteName(.a); fretboard.chordId = "m7"
            case "progression":
                fretboard.mode = .progression
            case "chordNone":
                fretboard.mode = .chord; fretboard.chordRoot = NoteName(.c); fretboard.chordId = "13#11"
            case "path":
                fretboard.pathKind = .threePerString
            case "path1":
                fretboard.pathKind = .oneString
            case "path4":
                fretboard.pathKind = .fourDiagonal
            case "search":
                // A C E G on an 8-string in Drop E: A on the 6th string, 5th fret; C, E, G nearby.
                fretboard.marked = [NeckSpot(course: 2, fret: 5), NeckSpot(course: 3, fret: 7), NeckSpot(course: 4, fret: 5), NeckSpot(course: 5, fret: 5)]
                fretboard.mode = .search
            default: break
            }
        }
        // Fretboard screenshot hooks of the new canvas boards live with the feature (FretboardController+Debug).
        fretboard.applyDebugArguments(arguments)
        if let i = arguments.firstIndex(of: "-sheet"), i + 1 < arguments.count {
            switch arguments[i + 1] {
            case "metroMeter": sheet = .metroMeter
            case "metroModes": sheet = .metroModes
            case "metroParams": sheet = .metroModeParams(.speedUp)
            case "metroFastSlow": sheet = .metroModeParams(.fastSlow)
            case "metroSong": sheet = .metroModeParams(.songMap)
            case "metroRandomMute": sheet = .metroModeParams(.randomMute)
            case "metroPresets": sheet = .metroPresets
            case "metroSounds": sheet = .metroSounds
            case "metroTimer": sheet = .metroTimer
            case "fretScale": sheet = .fretScale
            case "fretView": sheet = .fretView
            case "fretPlay": sheet = .fretPlay
            case "tunings": sheet = .tunings
            case "tuningsAdd": sheet = .tuningsAdd
            case "tuningEditor": sheet = .tuningEditor(tuning.id)
            case "library": sheet = .library
            case "templateCard": sheet = .templateCard("g8-standard-fs")
            case "generator": sheet = .generator
            case "instrument": sheet = .instrument
            case "instrumentRebuild": sheet = .instrumentRebuild(instrument.courses.count + 1)
            case "instrumentStrings": sheet = .instrumentStrings
            case "scaleBuilder": sheet = .scaleBuilder(nil)
            case "intonation": sheet = .intonation
            case "tunerPro": sheet = .tunerPro
            case "playCheck": sheet = .playCheck
            case "session": showSession = true
            #if DEBUG
            case "playCheckSummary": playCheck.injectDemo(); sheet = .playCheckSummary
            #endif
            case "trainerName", "trainerPlay":
                trainer.settings.kind = arguments[i + 1] == "trainerName" ? .nameNote : .playNote
                showTrainer = true
            case "chordBuilder": sheet = .chordBuilder(nil)
            case "userScales":
                settings.customScales = [Scale.user(id: "user-demo", name: "Фригийский с ♮7", semitones: [0, 1, 3, 5, 7, 8, 11])]
                UserLibrary.shared.set(scales: settings.customScales, chords: settings.customChords)
                fretboard.setScale("user-demo")
                sheet = .fretScale
            case "chordsFromNote": sheet = .chordsFromNote(2, 5)
            case "scaleFromNote": sheet = .scaleFromNote(2, 5)
            case "searchResults": sheet = .searchResults
            case "fretPath": sheet = .fretPath
            case "metroRhythm": sheet = .metroRhythm
            case "fretProgression": sheet = .fretProgression
            case "fretProgressions": sheet = .fretProgressions
            case "progressionFromNote": sheet = .progressionFromNote(2, 5)
            case "progressionChord": sheet = .progressionChord(1)
            case "progressionAdd": sheet = .progressionChord(nil)
            default: break
            }
        }
        // «Инструмент и строи» boards: `-tuningsDemo`, `-sheet tuningsLastOne | tuningsDelete | tuningUnsaved | …`.
        TuningsDebug.apply(arguments, app: self)
        if arguments.contains("-fretPlayTest") {
            Task { @MainActor [weak self] in
                guard let self else { return }
                @MainActor func log(_ tag: String) { let s = self.audio.host.debugNoteState(); print("PLAYTEST", tag, "voices", s.voices, "frames", s.frames, "metro", s.metronomeRunning, "peak", s.peak, "playing", self.fretboard.isPlaying) }
                try? await Task.sleep(for: .seconds(1.5))
                self.fretboard.startPlayback(); log("start1")
                if arguments.contains("-recordOutput") {
                    let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("out.caf")
                    try? FileManager.default.removeItem(at: url)
                    self.audio.host.debugRecordOutput(to: url, seconds: 16)
                }
                for i in 0..<12 { try? await Task.sleep(for: .milliseconds(250)); log("t1.\(i)") }
                self.fretboard.togglePlayback(); log("pause")
                try? await Task.sleep(for: .seconds(1))
                self.fretboard.togglePlayback(); log("start2")
                for i in 0..<28 { try? await Task.sleep(for: .milliseconds(250)); log("t2.\(i)") }
            }
        }
        if arguments.contains("-showSettings") || arguments.contains("-settingsPage") { showSettings = true }
        SettingsHooks.start(self)   // settings: saved noise threshold, rate prompt (`-ratePrompt`)
        #if DEBUG
        if arguments.contains("-trainingDemo") { fretboard.trainingDemo() }
        if arguments.contains("-playCheckHistoryDemo") { playCheck.injectHistoryDemo() }
        #endif
        if arguments.contains("-fretPlay") {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.fretboard.startPlayback()
            }
        }
        if arguments.contains("-beatFigures") {
            metronome.setRhythm(BeatRhythms.rhythm(id: "eighths"), beat: 0)
            metronome.setRhythm(BeatRhythms.rhythm(id: "triplets"), beat: 2)
            metronome.setRhythm(BeatRhythms.rhythm(id: "16:012"), beat: 3)
        }
        if arguments.contains("-progPlay") {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                self?.fretboard.progression.play()
            }
        }
        if arguments.contains("-metroPlay") {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.metronome.start()
            }
        }
    }

    // MARK: Derived

    var tuning: Tuning { instrument.currentTuning! }
    var a4: Double { tuning.effectiveA4(default: settings.defaultA4) }
    var formatter: NoteFormatter { NoteFormatter(notation: settings.notation, language: .ru) }
    /// Chord symbols: letters in solfège (canvas keeps «G♯°», «Am» in the key-chord strip); German stays German.
    var chordFormatter: NoteFormatter {
        NoteFormatter(notation: settings.notation == .solfege ? .international : settings.notation, language: .ru)
    }

    /// Tuning pill (canvas «8-струнная · Drop E»): the instrument word is dropped when the name starts with the
    /// string count; a custom name is shown as is.
    var title: String { "\(Self.shortInstrumentName(instrument.name)) · \(tuning.name)" }

    /// «8-струнная гитара» → «8-струнная»; old default names «Гитара, 8 струн» too (the switcher and the journal).
    static func shortInstrumentName(_ full: String) -> String {
        var name = full
        if let match = name.wholeMatch(of: /Гитара, (\d+) струн[аы]?/) { name = "\(match.1)-струнная гитара" }
        for word in [" гитара", " бас"] where name.hasSuffix(word) && name.first?.isNumber == true { name.removeLast(word.count) }
        return name
    }

    func noteName(_ note: SpelledNote) -> String { formatter.string(note) }

    /// Name of a string of the current tuning ("B1", "F♯1" or "H1" in German notation).
    func stringName(_ ref: StringRef) -> String {
        let pitch = tuning.openPitch(course: ref.course, string: ref.string)
        let main = tuning.spelledNotes[ref.course]
        return formatter.string(SpelledNote(main.name, midi: pitch.nearestMIDI))
    }

    /// Chromatic note name with the tuning's accidental family.
    func chromaticName(_ pitch: Pitch) -> String {
        let flats = tuning.spelledNotes.contains { $0.name.accidental < 0 }
        return formatter.string(SpelledNote(NoteName.simpleSpelling(ofPitchClass: pitch.pitchClass, preferFlats: flats),
                                            midi: pitch.nearestMIDI))
    }

    // MARK: Instrument edits

    var isSmartModeRunning: Bool { false }   // stage SM

    func updateInstrument(_ mutate: (inout Instrument) -> Void) {
        var copy = instrument
        mutate(&copy)
        guard copy != instrument else { return }
        let tuningChanged = copy.currentTuning != instrument.currentTuning || copy.courses != instrument.courses
        // A capo or another fret count moves the positions too (they stayed on the old frets).
        let neckChanged = copy.capo != instrument.capo || copy.fretCount != instrument.fretCount
        instrument = copy
        stored.update(copy)
        try? context.save()
        schedulePublish()
        if tuningChanged { tuner.tuningChanged() }
        if tuningChanged || neckChanged { fretboard.recompute(notifyPosition: true) }
    }

    func selectTuning(_ id: UUID) {
        updateInstrument { $0.currentTuningId = id }
    }

    func addTemplate(_ template: TuningTemplate) {
        if TuningTemplates.isCompatible(template, with: instrument) {
            updateInstrument { try? $0.addTuning(template.makeTuning()) }
        } else {
            replaceInstrument(with: template)
        }
    }

    /// 6.1 п. 19: a template of another type or string count replaces the instrument; the journal keeps its names.
    /// `fretCount`: the user's choice; nil keeps the current instrument's frets when the new one is of the same kind
    /// (a 22-fret guitar stays 22-fret after picking another guitar template — user request).
    func replaceInstrument(with template: TuningTemplate, fretCount: Int? = nil) {
        var replacement = template.makeInstrument()
        func family(_ t: InstrumentType) -> Int {
            switch t {
            case .guitar, .guitarExtendedHigh: return 0
            case .bass: return 1
            default: return 2
            }
        }
        if let fretCount {
            replacement.fretCount = fretCount
        } else if family(replacement.type) == family(instrument.type) && family(replacement.type) < 2 {
            replacement.fretCount = instrument.fretCount
        }
        context.delete(stored)
        let record = StoredInstrument(replacement)
        context.insert(record)
        stored = record
        instrument = replacement
        try? context.save()
        schedulePublish()
        tuner.tuningChanged()
        fretboard.recompute(notifyPosition: false)
    }

    func deleteTuning(_ id: UUID) {
        updateInstrument { try? $0.deleteTuning(id: id) }
    }

    /// The tuner listens only while its tab is open and onboarding is done (AU-4, 6.1 п. 1, 4).
    func updateListening() {
        // 6.1 п. 5: the tuner must not listen to the drone through the speaker.
        if settings.lastTab == .tuner { fretboard.stopDrone() }
        if (settings.lastTab == .tuner || trainer.needsMicrophone || playCheck.isOn) && !showOnboarding {
            Task { await tuner.start() }
        } else if tuner.isListening {
            tuner.stop()
        }
    }

    func show(_ text: String, icon: AppIcon? = nil, iconColor: Color = Theme.textSecondary) {
        noticeIcon = icon
        noticeIconColor = iconColor
        notice = text
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            if self?.notice == text { self?.notice = nil }
        }
    }
}

/// Sheets drawn by the app itself (canvas chrome) rather than by the system.
enum AppSheet: Hashable {
    case metroMeter, metroModes, metroModeParams(ModeParamKind), metroPresets, metroSounds, metroTimer, metroRhythm, metroRhythmBeat(Int)
    case fretScale, fretView, fretPlay
    case tunings, tuningsAdd, tuningEditor(UUID), library, templateCard(String), generator
    case instrument, instrumentRebuild(Int), instrumentStrings
    case chordsFromNote(Int, Int), scaleFromNote(Int, Int), searchResults, fretPath, fretProgression, progressionChord(Int?), progressionInsert(Int)
    case fretProgressions, progressionFromNote(Int, Int)
    /// TH-8: build or edit a user scale / chord (nil — a new one).
    case scaleBuilder(String?), chordBuilder(String?)
    /// TU-11 «Проверка мензуры».
    case intonation
    /// «Ещё» of the tuner (strobe, stage, noise gate).
    case tunerPro
    /// Stage SM: «Проверка игры» settings and the attempt summary.
    case playCheck, playCheckSummary
}

/// Which mode's parameters the parameters sheet edits.
enum ModeParamKind: Hashable { case speedUp, twoForward, fastSlow, songMap, displaced, gapBars, randomMute, ladder }
