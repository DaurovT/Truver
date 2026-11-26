import Foundation
import Observation
import TruverAudio
import TruverDSP
import TruverTheory

/// One dot on the neck.
struct NeckCell: Identifiable, Hashable {
    enum Emphasis: Hashable { case full, faint }
    var course: Int
    var fret: Int
    var pitch: Pitch
    var label: String
    var role: DegreeRole
    var emphasis: Emphasis
    var isAdded: Bool
    var isPlaying: Bool
    /// «Поиск»: a note marked by the user (purple).
    var isMarked = false
    /// The note a menu or a «from this note» sheet refers to (ring).
    var hasRing = false
    /// FB-14 / SM-5: played wrong in training (red).
    var isWrong = false
    var id: String { "\(course):\(fret)" }
}

/// FB-26: «Гамма · Аккорд · Поиск · Прогрессия».
enum FretMode: String, CaseIterable { case scale, chord, search, progression }

struct NeckSpot: Hashable { var course: Int; var fret: Int }

enum PlaybackChoice: String, CaseIterable, Identifiable {
    case up = "Подряд", thirds = "Терции", seq3 = "По 3", seq4 = "По 4"
    var id: String { rawValue }
    var pattern: PlaybackPattern {
        switch self {
        case .up: return .up
        case .thirds: return .thirds
        case .seq3: return .sequence(groupSize: 3)
        case .seq4: return .sequence(groupSize: 4)
        }
    }
}

/// Fretboard screen state (6.2.5): scale, positions (FB-4…FB-6), labels and colours (FB-2, FB-3), edits (FB-7),
/// playback (FB-8) and the key-chord strip (FB-17).
@MainActor
@Observable
final class FretboardController {
    weak var app: AppModel? { didSet { progression.app = app } }
    /// «Прогрессия» (FB-11, FB-22, FB-24).
    let progression = ProgressionController()

    private(set) var positions: [ScalePosition] = []
    private(set) var spelled: [NoteName] = []
    private(set) var keyChords: [KeyChord] = []

    // MARK: Drone (FB-13, SND-5)

    /// The tonic sounds as a steady organ-like tone until turned off; its level is the reference-tone slider.
    private(set) var isDroning = false

    /// The tonic between A2 and G♯3: low enough to sit under the scale, high enough for the phone speaker.
    var droneFrequency: Double {
        let pc = settings.tonic.pitchClass
        let midi = 45 + (pc - 9 + 12) % 12   // A2 = 45
        return Pitch(midi: Double(midi)).frequency(a4: app?.a4 ?? 440)
    }

    func toggleDrone() { isDroning ? stopDrone() : startDrone() }

    func startDrone() {
        guard let app else { return }
        try? app.audio.ensurePlayback()
        try? app.audio.host.startDrone(frequency: droneFrequency)
        isDroning = true
    }

    func stopDrone() {
        guard isDroning else { return }
        app?.audio.host.stopDrone()
        isDroning = false
    }

    // MARK: Modes (FB-26), chord (FB-9), search (FB-10), note menu (FB-21, FB-25)

    /// «Гриф | Таб» (canvas 2026-11-25): the tablature instead of the neck.
    var tabView = false
    /// Screenshot hook of S8Loupe (`-fretLoupe`): the screen shows the loupe over this cell on appear.
    var debugScrub: NeckSpot?
    /// Canvas FlowNote1: the tapped note — every note of the neck dim, this one big, «что построить от этой ноты?».
    var noteSpot: NeckSpot?
    /// The tab bar steps aside for the tablature and the note panel (RootView).
    var hidesTabBar: Bool { showsTabScreen || (noteSpot != nil && mode == .scale) }

    /// Canvas FlowNote1: the scale's notes dim (12 pt) and the tapped note marked (`hasRing`, 38 pt ivory).
    func allNoteCells() -> [NeckCell] {
        guard let app, let fretboard else { return [] }
        let spot = noteSpot
        var result = scaleCells().filter { NeckSpot(course: $0.course, fret: $0.fret) != spot }.map { cell -> NeckCell in
            var c = cell
            c.role = .other; c.emphasis = .full; c.hasRing = false; c.isPlaying = false
            return c
        }
        if let spot, let pitch = fretboard.pitch(course: spot.course, fret: spot.fret) {
            result.append(NeckCell(course: spot.course, fret: spot.fret, pitch: pitch, label: app.chromaticName(pitch).filter { !$0.isNumber },
                                   role: .other, emphasis: .full, isAdded: false, isPlaying: false, hasRing: true))
        }
        return result
    }

    /// Frets in view on the scrolling neck (canvas «Лады 1–12 из 24»): «Сыграть» plays the scale there.
    var playFrets: ClosedRange<Int> = 1...12

    /// Legend of the canvas: «G тоника», «B D аккорд» (the scale's 3rd and 5th roles).
    var legendNames: (tonic: String, chord: String) {
        guard let app, !spelled.isEmpty else { return ("", "") }
        let f = app.formatter
        let chord = spelled.indices.filter { $0 > 0 && scale.role(ofDegree: $0) == .chordTone }.map { f.string(spelled[$0]) }
        return (f.string(spelled[0]), chord.joined(separator: " "))
    }
    var mode: FretMode = .scale {
        didSet {
            // FB-26: the modes share the tonic; a chord picked in the strip opens as that chord.
            if mode == .chord && oldValue == .scale { syncChordFromScale() }
            if mode == .chord && voicings.isEmpty { recomputeVoicings() }
            if mode == .progression {
                if oldValue == .scale && progression.anchor == nil { progression.syncFromScale(scale, tonic: settings.tonic) }
                if progression.voiced.isEmpty { progression.recompute() }
            }
            if oldValue == .progression && mode != .progression && progression.isPlaying { progression.stop() }
        }
    }
    private func syncChordFromScale() {
        chordAnchor = nil
        chordBass = nil
        let picked = selectedChord.flatMap { keyChords[safe: $0] } ?? keyChords.first
        if let picked, let chord = picked.chord {
            chordRoot = picked.root
            chordId = chord.id
        } else {
            chordRoot = settings.tonic
            chordId = "maj"
        }
    }

    // «Аккорды от ноты» (FB-21): works on the chord state, which is put back when the sheet closes.
    private var savedChord: (root: NoteName, id: String, bass: Int?)?
    /// The voicing picked in the sheet: stands on the neck, the scale dimmed behind it.
    var chordPreview: ChordVoicing?

    func beginChordsFromNote(_ spot: NeckSpot, root: NoteName) {
        if savedChord == nil { savedChord = (chordRoot, chordId, chordBass) }
        chordBass = nil
        chordAnchor = spot
        chordRoot = root
        // The key's chord on this degree; major for a note outside the scale.
        let pitch = fretboard?.pitch(course: spot.course, fret: spot.fret)
        let index = pitch.flatMap { scale.degreeIndex(of: $0, tonic: settings.tonic) }
        chordId = index.flatMap { KeyChords.triads(scale, tonic: settings.tonic)?[safe: $0]?.chord?.id } ?? "maj"
    }

    func endChordsFromNote() {
        chordPreview = nil
        chordAnchor = nil
        guard let saved = savedChord else { return }
        savedChord = nil
        chordRoot = saved.root
        chordId = saved.id
        chordBass = saved.bass
    }

    var chordRoot = NoteName(.a) { didSet { recomputeVoicings() } }
    var chordId = "m7" { didSet { chordOmitted = []; recomputeVoicings() } }
    /// TH-3b: degrees dropped by «Опустить ступень N» (reset with the chord type).
    var chordOmitted: Set<DegreeLabel> = [] { didSet { recomputeVoicings() } }
    /// When nothing fits: the degree whose omission makes the chord playable.
    private(set) var omissionHint: DegreeLabel?
    /// Inversion: the pitch class in the bass (nil = root).
    var chordBass: Int? { didSet { recomputeVoicings() } }
    /// «Аккорды от ноты»: voicings must start from this cell.
    var chordAnchor: NeckSpot? { didSet { recomputeVoicings() } }
    private(set) var voicings: [ChordVoicing] = []
    var voicingIndex = 0
    var chordLabels: LabelMode = .notes
    /// «Поиск»: marked cells.
    var marked: [NeckSpot] = []
    /// Note menu target (long press).
    var menuSpot: NeckSpot?
    /// «Гамма от ноты»: the position that contains this cell with the tonic on it («позиция от ноты»).
    var positionAnchor: NeckSpot?
    /// FB-25: the position built from that cell (the note is its lowest), until an arrow or another view is chosen.
    private(set) var anchoredPosition: ScalePosition?

    /// «Гамма от ноты» while the sheet is open: this scale from this note stands on the neck (canvas «превью»).
    struct ScaleNotePreview {
        var position: ScalePosition
        var scale: Scale
        var tonic: NoteName
        var spot: NeckSpot
    }
    private(set) var fromNotePreview: ScaleNotePreview?
    var hasPreview: Bool { chordPreview != nil || fromNotePreview != nil }

    private var layoutOptions: LayoutOptions {
        LayoutOptions(allowOpenStrings: settings.allowOpenStrings, eightNotePattern: settings.eightNotePattern)
    }

    func previewScale(from spot: NeckSpot, scaleId: String) {
        guard let fretboard, let pitch = fretboard.pitch(course: spot.course, fret: spot.fret),
              let scale = ScaleLibrary.scale(id: scaleId) else { fromNotePreview = nil; return }
        let tonic = ScaleSpeller.preferredTonic(pitchClass: pitch.pitchClass, scale: scale)
        fromNotePreview = PositionLayout.position(from: (spot.course, spot.fret), kind: settings.layout, scale: scale, tonic: tonic,
                                                  on: fretboard, options: layoutOptions)
            .map { ScaleNotePreview(position: $0, scale: scale, tonic: tonic, spot: spot) }
    }

    func endScalePreview() { fromNotePreview = nil }

    private func previewCells(_ p: ScaleNotePreview) -> [NeckCell] {
        guard let app else { return [] }
        let spelled = ScaleSpeller.spell(p.scale, tonic: p.tonic)
        return zip(p.position.notes, p.position.fingers).map { n, finger in
            let degree = p.scale.degreeIndex(of: n.pitch, tonic: p.tonic) ?? 0
            let label: String
            switch settings.labels {
            case .notes: label = app.formatter.string(spelled[degree])
            case .degrees: label = p.scale.degrees[degree].label.description
            case .intervals: label = Self.intervalName(p.scale.degrees[degree].semitones)
            case .fingers: label = String(finger)
            case .none: label = ""
            }
            return NeckCell(course: n.course, fret: n.fret, pitch: n.pitch, label: label, role: p.scale.role(ofDegree: degree),
                            emphasis: .full, isAdded: false, isPlaying: false, hasRing: NeckSpot(course: n.course, fret: n.fret) == p.spot)
        }
    }

    // MARK: Path (FB-20)

    /// Path mode inside «Гамма»: nil = off.
    var pathKind: PathKind? { didSet { recomputePath() } }
    var pathStart: NeckSpot? { didSet { recomputePath() } }
    private(set) var pathNotes: [FretNote] = []

    /// Index of the sounding path note while playing.
    var pathIndex: Int? {
        guard let p = playingNote else { return nil }
        return pathNotes.firstIndex { $0.course == p.course && $0.fret == p.fret }
    }

    func recomputePath() {
        clearPause()
        guard let kind = pathKind, let fretboard else { pathNotes = []; return }
        let start = pathStart.map { ($0.course, $0.fret) } ?? defaultPathStart()
        guard let start else { pathNotes = []; return }
        pathNotes = ScalePath.build(kind, scale: scale, tonic: settings.tonic, on: fretboard, start: start)
    }

    /// The lowest tonic on the lowest string.
    private func defaultPathStart() -> (Int, Int)? {
        guard let fretboard else { return nil }
        for fret in 0...fretboard.instrument.fretCount {
            if let p = fretboard.pitch(course: 0, fret: fret), p.pitchClass == settings.tonic.pitchClass { return (0, fret) }
        }
        return nil
    }

    /// Label inside a path note: what the neck shows (note, degree, interval); numbers are the badge.
    func pathLabel(_ n: FretNote) -> String {
        guard let app else { return "" }
        let degree = scale.degreeIndex(of: n.pitch, tonic: settings.tonic)
        switch settings.labels {
        case .degrees: return degree.map { scale.degrees[$0].label.description } ?? ""
        case .intervals: return degree.map { Self.intervalName(scale.degrees[$0].semitones) } ?? ""
        default: return degree.flatMap { spelled[safe: $0] }.map { app.formatter.string($0) } ?? app.chromaticName(n.pitch).filter { !$0.isNumber }
        }
    }

    /// «4 ноты наискосок · 24 ноты · от G2, 6-я струна» — what the path is, before it plays.
    var pathSummary: String {
        guard let app, let first = pathNotes.first, let kind = pathKind else { return "" }
        let kindText: String
        switch kind {
        case .threePerString: kindText = "3 на струну"
        case .fourDiagonal: kindText = "4 наискосок"
        case .oneString: kindText = "по одной струне"
        }
        let n = pathNotes.count
        let notes = n % 10 == 1 && n % 100 != 11 ? "нота" : ((2...4).contains(n % 10) && !(12...14).contains(n % 100) ? "ноты" : "нот")
        return "\(kindText) · \(n) \(notes) · от \(app.chromaticName(first.pitch)), \(app.instrument.courses.count - first.course)-я стр."
    }

    func startPath(from spot: NeckSpot?) {
        mode = .scale
        pathStart = spot
        // «Путь отсюда» leads across the neck from the pressed note (3 per string stayed in one position and looked
        // like the position itself — user: «не понятно, что даёт»); the visible «Путь» keeps position by position.
        if pathKind == nil { pathKind = spot != nil ? .fourDiagonal : .threePerString } else { recomputePath() }

    }

    var chord: Chord {
        let base = ChordLibrary.anyChord(id: chordId) ?? ChordLibrary.minor7
        return chordOmitted.isEmpty ? base : base.omitting(chordOmitted)
    }
    var currentVoicing: ChordVoicing? { voicings[safe: voicingIndex] }

    func recomputeVoicings() {
        guard let fretboard else { voicings = []; return }
        let anchor = chordAnchor.map { ($0.course, $0.fret) }
        voicings = ChordVoicings.voicings(chord: chord, root: chordRoot, on: fretboard, bassPitchClass: chordBass,
                                          anchor: anchor, limit: 30)
        omissionHint = voicings.isEmpty ? ChordVoicings.omissionHint(chord: chord, root: chordRoot, on: fretboard, anchor: anchor, knownEmpty: true) : nil
        voicingIndex = 0
    }

    func chordName(_ root: NoteName? = nil, _ chord: Chord? = nil, bass: Int? = nil) -> String {
        guard let app else { return "" }
        let r = root ?? chordRoot, c = chord ?? self.chord
        var name = compactChordName(c.name(root: r, formatter: app.formatter))
        if chord == nil, !chordOmitted.isEmpty {
            name += " без " + chordOmitted.map { String($0.number) }.sorted().joined(separator: ", ")
        }
        if let bass, bass != r.pitchClass, let b = c.spell(root: r).first(where: { $0.pitchClass == bass }) {
            name += "/" + app.formatter.string(b)
        }
        return name
    }

    /// «открытый», «баррэ», «4 струны», «вниз по грифу», «от 5-го лада» (canvas list rows).
    func voicingTitle(_ v: ChordVoicing) -> String {
        if v.usesOpenStrings && v.lowestFret <= 4 { return "открытый" }
        if let anchor = chordAnchor, v.notes.contains(where: { $0.fret < anchor.fret && $0.fret > 0 }) { return "вниз по грифу" }
        return "от \(v.lowestFret)-го лада"
    }

    /// «тоника на 6-й струне · 3 пальца», «с басом B0-струны · 5 нот · баррэ».
    func voicingSubtitle(_ v: ChordVoicing) -> String {
        guard let app else { return "" }
        let n = app.instrument.courses.count
        var parts: [String] = []
        let bassString = n - v.bass.course
        if v.bass.pitch.pitchClass == chordRoot.pitchClass {
            parts.append("тоника на \(bassString)-й")
        } else {
            parts.append("бас \(app.chromaticName(v.bass.pitch).filter { !$0.isNumber }) на \(bassString)-й")
        }
        parts.append("\(v.notes.count) стр.")
        if v.barreFret != nil { parts.append("баррэ") } else { parts.append("\(v.fingers) \(ruPlural(v.fingers, "палец", "пальца", "пальцев"))") }
        return parts.joined(separator: " · ")
    }

    func stepVoicing(_ delta: Int) {
        guard !voicings.isEmpty else { return }
        voicingIndex = (voicingIndex + delta + voicings.count) % voicings.count
    }

    /// Strums the current voicing (FB-23): low to high, 12 ms per string, 2 s.
    func playVoicing(_ voicing: ChordVoicing? = nil, arpeggio: Bool = false) {
        guard let app, let v = voicing ?? currentVoicing else { return }
        let step = arpeggio ? 60 / app.metronome.bpm / 2 : 0.012
        let sequence = v.notes.enumerated().map { (i, n) in (frequency: n.pitch.frequency(a4: app.a4), offset: Double(i) * step) }
        do {
            try app.audio.ensurePlayback()
            app.tuner.pauseForPlayback(seconds: 2.15 + Double(v.notes.count) * step)
            app.audio.host.stopNotes()
            _ = try app.audio.host.playNotes(sequence, start: .now(delay: 0.02), velocity: 0.75, strings: v.notes.map(\.course),
                                             noteDuration: arpeggio ? nil : 2)
        } catch {
            app.show("Звук недоступен")
        }
        strumOrder = v.notes.map(\.course)
        strumming = Set(strumOrder)
        strumTask?.cancel()
        strumTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.strumming = []
        }
    }

    // Search
    func toggleMark(course: Int, fret: Int) {
        let spot = NeckSpot(course: course, fret: fret)
        if let i = marked.firstIndex(of: spot) { marked.remove(at: i) } else {
            // One note per string, as on a real neck.
            marked.removeAll { $0.course == course }
            marked.append(spot)
        }
    }

    var markedPitches: [Pitch] {
        marked.compactMap { fretboard?.pitch(course: $0.course, fret: $0.fret) }.sorted { $0.cents < $1.cents }
    }

    var searchChords: [ChordMatch] {
        let pitches = markedPitches
        guard pitches.count >= 3 else { return [] }
        return ChordRecognizer.identify(pitchClasses: Set(pitches.map(\.pitchClass)), bass: pitches.first?.pitchClass,
                                        preferFlats: spelled.contains { $0.accidental < 0 })
    }

    var searchScales: [ScaleMatch] {
        let pitches = markedPitches
        guard pitches.count >= 3 else { return [] }
        return ScaleFinder.scales(containing: Set(pitches.map(\.pitchClass)), preferredTonic: pitches.first?.pitchClass)
    }

    /// «Открыть в «Аккорде»».
    func openInChordMode(_ match: ChordMatch) {
        chordAnchor = nil
        chordBass = match.bass?.pitchClass
        chordRoot = match.root
        chordId = match.chord.id
        mode = .chord
    }

    /// «Гамма от этой ноты» (FB-25): tonic = the note, position = the one that holds this cell.
    func buildScale(from spot: NeckSpot, scaleId: String) {
        guard let pitch = fretboard?.pitch(course: spot.course, fret: spot.fret) else { return }
        var s = settings
        s.scaleId = scaleId
        if let scale = ScaleLibrary.scale(id: scaleId) { s.tonic = ScaleSpeller.preferredTonic(pitchClass: pitch.pitchClass, scale: scale) }
        s.hiddenCells = []; s.addedCells = []
        s.neckView = .position
        settings = s
        if let number = positions.first(where: { p in p.notes.contains { $0.course == spot.course && $0.fret == spot.fret } && p.notes.first?.course == spot.course })?.number
            ?? positions.first(where: { p in p.notes.contains { $0.course == spot.course && $0.fret == spot.fret } })?.number {
            selectPosition(number)
        }
        positionAnchor = spot
        anchoredPosition = fretboard.flatMap {
            PositionLayout.position(from: (spot.course, spot.fret), kind: settings.layout, scale: scale, tonic: settings.tonic,
                                    on: $0, options: layoutOptions)
        }
        mode = .scale
    }
    var showSevenths = false { didSet { recomputeChords() } }
    var selectedChord: Int?
    /// Playback pattern, direction and loop (FB-8; user: «вверх-вниз, по кругу»). Kept in UserDefaults.
    var playback: PlaybackChoice = PlaybackChoice(rawValue: UserDefaults.standard.string(forKey: "fb.pattern") ?? "") ?? .up {
        didSet { UserDefaults.standard.set(playback.rawValue, forKey: "fb.pattern") }
    }
    var direction: PlaybackDirection = PlaybackDirection(rawValue: UserDefaults.standard.string(forKey: "fb.direction") ?? "") ?? .up {
        didSet { UserDefaults.standard.set(direction.rawValue, forKey: "fb.direction") }
    }
    /// «Вид и подписи» → «Ноты вне гаммы»: the other notes of the neck, dimmed (canvas 2026-11-25).
    var showOutOfScale: Bool = UserDefaults.standard.bool(forKey: "fb.outOfScale") {
        didSet { UserDefaults.standard.set(showOutOfScale, forKey: "fb.outOfScale") }
    }
    /// «Вид и подписи» → «Лады от капо»: fret numbers count from the capo.
    var fretsFromCapo: Bool = ProcessInfo.processInfo.arguments.contains("-fretsFromCapoOff") ? false : (UserDefaults.standard.object(forKey: "fb.fretsFromCapo") as? Bool ?? true) {
        didSet { UserDefaults.standard.set(fretsFromCapo, forKey: "fb.fretsFromCapo") }
    }
    var loop: Bool = UserDefaults.standard.bool(forKey: "fb.loop") {
        didSet { UserDefaults.standard.set(loop, forKey: "fb.loop") }
    }
    private(set) var isPlaying = false
    private(set) var playingNote: (course: Int, fret: Int)?
    private var playTask: Task<Void, Never>?
    /// «Пауза» keeps the place (iPhone UX check: it restarted from the first note): the next start continues from
    /// `resumeIndex` in the play order while the notes and the order are the same (`resumeKey`).
    private var resumeIndex: Int?
    private var resumeKey: [Int] = []
    /// Position in the play order of the note being heard.
    private var orderPosition: Int?
    private var resumeOrderCount = 0
    /// Paused in the middle: «Сыграть» continues.
    var canResume: Bool { !isPlaying && resumeIndex != nil }

    private func playKey(_ notes: [FretNote], _ order: [Int]) -> [Int] {
        notes.flatMap { [$0.course, $0.fret] } + [-1] + order
    }

    /// Forget the paused place (the scale, position or path changed).
    func clearPause() {
        guard !isPlaying else { return }
        resumeIndex = nil
        playingNote = nil
    }

    var settings: FretboardSettings {
        get { app?.settings.fretboard ?? FretboardSettings() }
        set {
            let old = settings
            app?.settings.fretboard = newValue
            if newValue.tonic != old.tonic && isDroning { startDrone() }   // FB-13: the drone follows the tonic
            if newValue.scaleId != old.scaleId || newValue.tonic != old.tonic || newValue.layout != old.layout
                || newValue.allowOpenStrings != old.allowOpenStrings || newValue.eightNotePattern != old.eightNotePattern {
                recompute()
            }
        }
    }

    var scale: Scale { ScaleLibrary.scale(id: settings.scaleId) ?? ScaleLibrary.major }

    var fretboard: Fretboard? { app.flatMap { Fretboard(instrument: $0.instrument) } }

    var scaleTitle: String {
        guard let app else { return "" }
        // Solfège (canvas): «ми · фригийский доминант» — the scale name in lower case after a syllable.
        let name = app.settings.notation == .solfege ? scale.names.ru.lowercased() : scale.names.ru
        return "\(app.formatter.string(settings.tonic)) · \(name)"
    }

    var currentPosition: ScalePosition? {
        guard settings.neckView == .position else { return nil }
        if positionAnchor != nil, let anchoredPosition { return anchoredPosition }
        return positions.first { $0.number == settings.positionNumber } ?? positions.first
    }

    // MARK: Recompute

    func recompute(notifyPosition: Bool = false) {
        clearPause()
        defer {
            if pathKind != nil { recomputePath() }
            refreshAnchoredPosition()
            progression.instrumentMayHaveChanged()
        }
        guard let fretboard else { return }
        let previous = currentPosition?.fretRange
        spelled = ScaleSpeller.spell(scale, tonic: settings.tonic)
        let options = LayoutOptions(allowOpenStrings: settings.allowOpenStrings, eightNotePattern: settings.eightNotePattern)
        positions = PositionLayout.positions(settings.layout, scale: scale, tonic: settings.tonic, on: fretboard, options: options)
        // 6.1 п. 18: keep the position whose window is closest to the previous one.
        if let previous, !positions.isEmpty, notifyPosition {
            let best = positions.min { a, b in
                let da = abs(a.fretRange.lowerBound - previous.lowerBound), db = abs(b.fretRange.lowerBound - previous.lowerBound)
                return da == db ? a.fretRange.lowerBound < b.fretRange.lowerBound : da < db
            }!
            if best.number != settings.positionNumber { showToast("Позиция пересчитана под новый строй") }
            app?.settings.fretboard.positionNumber = best.number
        } else if settings.positionNumber > positions.count {
            app?.settings.fretboard.positionNumber = 1
        }
        if positions.isEmpty && settings.neckView == .position { app?.settings.fretboard.neckView = .wholeNeck }
        recomputeChords()
    }

    private func recomputeChords() {
        let chords = showSevenths ? KeyChords.sevenths(scale, tonic: settings.tonic) : KeyChords.triads(scale, tonic: settings.tonic)
        keyChords = chords ?? []
        selectedChord = nil
    }

    // MARK: Cells

    func cells() -> [NeckCell] {
        if let preview = fromNotePreview { return previewCells(preview) }
        if let preview = chordPreview {
            // The picked voicing in full, the scale faint behind it (canvas «Аккорды от ноты — звучит»).
            let shown = chordCells(preview)
            let taken = Set(shown.map(\.id))
            var dim = scaleCells().filter { !taken.contains($0.id) }
            for i in dim.indices { dim[i].emphasis = .faint; dim[i].label = "" }
            return dim + shown
        }
        if noteSpot != nil && mode == .scale { return allNoteCells() }
        switch mode {
        case .chord: return currentVoicing.map(chordCells) ?? []
        case .search: return searchCells()
        case .scale: return scaleCells()
        case .progression: return progression.cells()
        }
    }

    /// Chord mode: the voicing's notes; root ivory, 3rd and 5th blue, the rest dark (canvas «Режим «Аккорд»»).
    private func chordCells(_ v: ChordVoicing) -> [NeckCell] {
        guard let app else { return [] }
        let spelled = chord.spell(root: chordRoot)
        return v.notes.map { n in
            let degree = chord.degrees.first { (chordRoot.pitchClass + $0.semitones) % 12 == n.pitch.pitchClass }
            let role: DegreeRole
            if n.pitch.pitchClass == chordRoot.pitchClass { role = .tonic }
            else if let d = degree, [3, 5].contains(d.label.number) { role = .chordTone }
            else { role = .other }
            let name = spelled.first { $0.pitchClass == n.pitch.pitchClass }.map { app.formatter.string($0) } ?? app.chromaticName(n.pitch)
            let label: String
            switch chordLabels {
            case .degrees: label = degree?.label.description ?? ""
            case .fingers: label = String(v.fingerNumbers[n.course] ?? 0)
            default: label = name
            }
            return NeckCell(course: n.course, fret: n.fret, pitch: n.pitch, label: label, role: role, emphasis: .full,
                            isAdded: false, isPlaying: false, hasRing: chordAnchor == NeckSpot(course: n.course, fret: n.fret))
        }
    }

    /// Search mode: only the marked notes (purple).
    private func searchCells() -> [NeckCell] {
        guard let app, let fretboard else { return [] }
        return marked.compactMap { spot in
            guard let p = fretboard.pitch(course: spot.course, fret: spot.fret) else { return nil }
            return NeckCell(course: spot.course, fret: spot.fret, pitch: p, label: app.chromaticName(p).filter { !$0.isNumber }, role: .other, emphasis: .full,
                            isAdded: false, isPlaying: false, isMarked: true)
        }
    }

    private func scaleCells() -> [NeckCell] {
        guard let app, let fretboard else { return [] }
        let formatter = app.formatter
        let s = settings
        let hidden = Set(s.hiddenCells), added = Set(s.addedCells)
        let position = currentPosition
        var positionFingers: [String: Int] = [:]
        if let position {
            for (note, finger) in zip(position.notes, position.fingers) { positionFingers["\(note.course):\(note.fret)"] = finger }
        }
        let chordPitchClasses: Set<Int>? = selectedChord.flatMap { keyChords[safe: $0] }.map { Set($0.notes.map(\.pitchClass)) }
        let flats = spelled.contains { $0.accidental < 0 }

        var result: [NeckCell] = []
        for course in 0..<fretboard.courseCount {
            for fret in app.instrument.playableFrets(course: course) {
                let key = "\(course):\(fret)"
                guard !hidden.contains(key), let pitch = fretboard.pitch(course: course, fret: fret) else { continue }
                let degree = scale.degreeIndex(of: pitch, tonic: s.tonic)
                let isAdded = degree == nil && added.contains(key)
                // «Ноты вне гаммы» (sheet «Вид и подписи»): the other notes stay, faint.
                let outside = degree == nil && !isAdded && showOutOfScale && mode == .scale
                guard degree != nil || isAdded || outside else { continue }

                var emphasis = NeckCell.Emphasis.full
                switch s.neckView {
                case .wholeNeck: break
                // Position view shows only the notes that the position plays (user: «зачем ноты, которые не
                // воспроизводятся?»); the whole scale is one tap away («Весь гриф»).
                // Canvas 2026-11-25: the whole neck scrolls; positions only narrow the notes while training.
                case .position: if isTraining && positionFingers[key] == nil && !isAdded && pathKind == nil { continue }
                case .window: if !(s.windowStart...(s.windowStart + s.windowLength - 1)).contains(fret) && fret != 0 { emphasis = .faint }
                }
                if let chordPitchClasses { emphasis = chordPitchClasses.contains(pitch.pitchClass) ? .full : .faint }
                if outside { emphasis = .faint }

                let label: String
                if let degree {
                    switch s.labels {
                    case .notes: label = formatter.string(spelled[degree])
                    case .degrees: label = scale.degrees[degree].label.description
                    case .intervals: label = Self.intervalName(scale.degrees[degree].semitones)
                    case .fingers: label = positionFingers[key].map(String.init) ?? ""
                    case .none: label = ""
                    }
                } else {
                    label = s.labels == .none ? "" : formatter.string(NoteName.simpleSpelling(ofPitchClass: pitch.pitchClass, preferFlats: flats))
                }
                let role: DegreeRole = degree.map { scale.role(ofDegree: $0) } ?? .other
                let playing = playingNote.map { $0.course == course && $0.fret == fret } ?? false
                let spot = NeckSpot(course: course, fret: fret)
                result.append(NeckCell(course: course, fret: fret, pitch: pitch, label: label, role: role,
                                       emphasis: emphasis, isAdded: isAdded, isPlaying: playing,
                                       hasRing: positionAnchor == spot || menuSpot == spot, isWrong: wrongSpots.contains(spot)))
            }
        }
        return result
    }

    static func intervalName(_ semitones: Int) -> String {
        ["ч1", "м2", "б2", "м3", "б3", "ч4", "тт", "ч5", "м6", "б6", "м7", "б7"][mod12(semitones)]
    }

    private static func mod12(_ v: Int) -> Int { ((v % 12) + 12) % 12 }

    // MARK: Interaction

    /// FB-7: a tap sounds the note.
    func tap(course: Int, fret: Int) {
        guard let app, let pitch = fretboard?.pitch(course: course, fret: fret) else { return }
        app.tuner.pauseForPlayback(seconds: 2.15)   // FB-23: the microphone ignores the phone's own note
        app.audio.playNote(pitch, a4: app.a4, string: course)
    }

    /// FB-7: a long tap hides a scale note or adds a note that is not in the scale (6.1 п. 13).
    func toggle(course: Int, fret: Int) {
        guard let pitch = fretboard?.pitch(course: course, fret: fret) else { return }
        let key = "\(course):\(fret)"
        var s = settings
        if scale.degreeIndex(of: pitch, tonic: s.tonic) != nil {
            if let i = s.hiddenCells.firstIndex(of: key) { s.hiddenCells.remove(at: i) } else { s.hiddenCells.append(key) }
        } else {
            if let i = s.addedCells.firstIndex(of: key) { s.addedCells.remove(at: i) } else { s.addedCells.append(key) }
        }
        settings = s
    }

    /// The note's name as the scale spells it (chromatic outside the scale), for the note menu.
    func noteName(_ spot: NeckSpot) -> String {
        guard let app, let pitch = fretboard?.pitch(course: spot.course, fret: spot.fret) else { return "" }
        if let degree = scale.degreeIndex(of: pitch, tonic: settings.tonic), spelled.indices.contains(degree) {
            return app.formatter.short(spelled[degree])
        }
        return app.chromaticName(pitch).filter { !$0.isNumber }
    }

    func isHidden(_ spot: NeckSpot) -> Bool { settings.hiddenCells.contains("\(spot.course):\(spot.fret)") }

    var isEdited: Bool { !settings.hiddenCells.isEmpty || !settings.addedCells.isEmpty }

    func resetEdits() {
        var s = settings
        s.hiddenCells = []
        s.addedCells = []
        settings = s
    }

    /// The position from a note lives while that note is still the tonic (layout changes rebuild it).
    private func refreshAnchoredPosition() {
        guard let spot = positionAnchor else { return }
        guard let fretboard, let pitch = fretboard.pitch(course: spot.course, fret: spot.fret),
              pitch.pitchClass == settings.tonic.pitchClass,
              let rebuilt = PositionLayout.position(from: (spot.course, spot.fret), kind: settings.layout, scale: scale,
                                                    tonic: settings.tonic, on: fretboard, options: layoutOptions) else {
            positionAnchor = nil
            anchoredPosition = nil
            return
        }
        anchoredPosition = rebuilt
    }

    func selectPosition(_ number: Int?) {
        positionAnchor = nil
        anchoredPosition = nil
        var s = settings
        if let number {
            s.neckView = .position
            s.positionNumber = number
        } else {
            s.neckView = .wholeNeck
        }
        settings = s
    }

    func stepPosition(_ delta: Int) {
        guard !positions.isEmpty else { return }
        let current = settings.neckView == .position ? settings.positionNumber : 0
        let next = min(positions.count, max(1, current + delta))
        selectPosition(next)
    }

    func setTonic(pitchClass: Int) {
        var s = settings
        s.tonic = ScaleSpeller.preferredTonic(pitchClass: pitchClass, scale: scale)
        s.hiddenCells = []
        s.addedCells = []
        settings = s
    }

    /// Manual enharmonic switch (5.2.1 rule 6): G♯ ↔ A♭.
    func toggleEnharmonic() {
        let options = NoteName.simpleSpellings(ofPitchClass: settings.tonic.pitchClass).filter { $0 != settings.tonic }
        guard let other = options.min(by: { abs($0.accidental) < abs($1.accidental) }) else { return }
        var s = settings
        s.tonic = other
        settings = s
    }

    /// TH-8 «Сохранить как свою»: the scale's notes with the neck edits (added notes in, hidden notes out),
    /// as semitones above the tonic.
    var editedSemitones: [Int] {
        guard let fretboard else { return scale.semitoneSet }
        let tonic = settings.tonic.pitchClass
        func pc(_ key: String) -> Int? {
            let parts = key.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2, let p = fretboard.pitch(course: parts[0], fret: parts[1]) else { return nil }
            return ((p.pitchClass - tonic) % 12 + 12) % 12
        }
        var set = Set(scale.semitoneSet)
        let added = Set(settings.addedCells.compactMap(pc))
        set.subtract(Set(settings.hiddenCells.compactMap(pc)).subtracting(added))
        set.formUnion(added)
        set.insert(0)
        return set.sorted()
    }

    func setScale(_ id: String) {
        var s = settings
        s.scaleId = id
        s.hiddenCells = []
        s.addedCells = []
        if let scale = ScaleLibrary.scale(id: id) {
            s.tonic = ScaleSpeller.preferredTonic(pitchClass: s.tonic.pitchClass, scale: scale)
        }
        settings = s
    }

    // MARK: Playback (FB-8, 6.1 п. 14)

    func togglePlayback() { isPlaying ? stopPlayback() : startPlayback() }

    /// What «Сыграть» plays is what is on the screen (it played position 1 from any view): the path, the position,
    /// the notes of the custom window; from «Весь гриф» it moves to the first position and says so.
    private func notesToPlay() -> [FretNote] {
        if pathKind != nil, !pathNotes.isEmpty { return pathNotes }
        switch settings.neckView {
        case .window:
            return notes(in: visibleFrets)
        case .position, .wholeNeck:
            // The frets in view on the scrolling neck, open strings included at the top.
            return notes(in: (playFrets.lowerBound <= 1 ? 0 : playFrets.lowerBound)...playFrets.upperBound)
        }
    }

    /// Scale notes inside `frets`, low to high, each pitch once (on the lower string).
    private func notes(in frets: ClosedRange<Int>) -> [FretNote] {
        var seen = Set<Int>()
        return scaleCells()
            .filter { frets.contains($0.fret) }
            .sorted { $0.pitch.cents == $1.pitch.cents ? $0.course < $1.course : $0.pitch.cents < $1.pitch.cents }
            .filter { seen.insert(Int($0.pitch.cents.rounded())).inserted }
            .map { FretNote(course: $0.course, fret: $0.fret, pitch: $0.pitch,
                            degreeIndex: scale.degreeIndex(of: $0.pitch, tonic: settings.tonic) ?? 0) }
    }

    // MARK: FB-14 «Тренировать»: the shown notes in the playback order, one per click; the microphone checks
    // time and pitch (stage SM), the tempo follows the result.

    private(set) var isTraining = false
    private(set) var wrongSpots: Set<NeckSpot> = []
    private var trainingNotes: [FretNote] = []
    private var wrongTasks: [NeckSpot: Task<Void, Never>] = [:]

    func startTraining() {
        guard let app else { return }
        if isPlaying { stopPlayback() }
        let notes = notesToPlay()
        let order = playback.pattern.cycle(noteCount: notes.count, direction: direction, loop: true)
        guard !order.isEmpty else { return }
        trainingNotes = order.map { notes[$0] }
        isTraining = true
        wrongSpots = []
        app.playCheck.beginExercise(pitches: trainingNotes.map(\.pitch), onNote: { [weak self] index in
            guard let self, let n = self.trainingNotes[safe: index] else { return }
            self.playingNote = (n.course, n.fret)
        }, onWrong: { [weak self] index in
            guard let self, let n = self.trainingNotes[safe: index] else { return }
            self.markWrong(NeckSpot(course: n.course, fret: n.fret))
        })
        Task {
            await app.playCheck.enable()
            guard app.playCheck.isOn else { stopTraining(); return }
            if !app.metronome.isPlaying { app.metronome.start() }
        }
    }

    #if DEBUG
    /// Screenshot hook `-trainingDemo`: the training layout without the microphone.
    func trainingDemo() {
        isTraining = true
        let notes = notesToPlay()
        if let n = notes[safe: 2] { playingNote = (n.course, n.fret) }
        if let w = notes[safe: 4] { wrongSpots = [NeckSpot(course: w.course, fret: w.fret)] }
    }
    #endif

    func stopTraining() {
        guard isTraining else { return }
        isTraining = false
        playingNote = nil
        wrongSpots = []
        app?.metronome.stop()
        app?.playCheck.endExercise()
        app?.playCheck.disable()
    }

    private func markWrong(_ spot: NeckSpot) {
        wrongSpots.insert(spot)
        wrongTasks[spot]?.cancel()
        wrongTasks[spot] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            self?.wrongSpots.remove(spot)
        }
    }

    func startPlayback() {
        guard let app else { return }
        let notes = notesToPlay()
        guard !notes.isEmpty else { return }
        let order = playback.pattern.cycle(noteCount: notes.count, direction: direction, loop: loop)
        guard !order.isEmpty else { return }
        let key = playKey(notes, order)
        let startIndex = (resumeKey == key ? resumeIndex : nil).map { min($0, order.count - 1) } ?? 0
        resumeIndex = nil
        let meter = app.metronome.meter
        let step = 60 / meter.bpm / Double(max(1, meter.subdivision == 1 ? 2 : meter.subdivision))
        let bar = 60 / meter.bpm * Double(meter.numerator)

        var countIn: TimeInterval = 0
        if !app.metronome.isPlaying && settings.clickWithPlayback {
            app.metronome.start(byPlayback: true)
            countIn = bar   // one bar of count-in
        }
        func sequence(_ indices: [Int], _ offset: TimeInterval) -> [(frequency: Double, offset: TimeInterval)] {
            indices.enumerated().map { (i, index) in (frequency: notes[index].pitch.frequency(a4: app.a4), offset: offset + Double(i) * step) }
        }
        let first = Array(order[startIndex...])
        let cycleLength = Double(order.count) * step
        let looping = loop   // a change applies to the next start
        do {
            try app.audio.ensurePlayback()
            let start: AudioEngineHost.NoteStart = app.metronome.isPlaying ? .nextBar(fallbackDelay: 0.1) : .now(delay: 0.1)
            // FB-8: each note on its own string and fret, one subdivision long, no overlap.
            let lead = try app.audio.host.playNotes(sequence(first, countIn), start: start, strings: first.map { notes[$0].course },
                                                    noteDuration: step)
            let firstSample = app.audio.host.lastNotesStartSample
            let rate = app.audio.host.noteSampleRate
            isPlaying = true
            resumeKey = key
            resumeOrderCount = order.count
            playTask?.cancel()
            playTask = Task { [weak self] in
                let clock = ContinuousClock()
                let t0 = clock.now + .seconds(lead + countIn)
                var passStart = 0.0
                var pass = 0
                repeat {
                    let indices = pass == 0 ? first : order
                    let offset = pass == 0 ? startIndex : 0
                    let passLength = Double(indices.count) * step
                    // Loop: the next pass is scheduled one pass ahead, at an exact sample — no gap, no drift.
                    if looping {
                        let next = firstSample + Int64((countIn + passStart + passLength) * rate)
                        _ = try? self?.app?.audio.host.playNotes(sequence(order, 0), start: .sample(next),
                                                                 strings: order.map { notes[$0].course }, noteDuration: step)
                    }
                    for (i, index) in indices.enumerated() {
                        try? await clock.sleep(until: t0 + .seconds(passStart + Double(i) * step))
                        guard let self, !Task.isCancelled else { return }
                        self.playingNote = (notes[index].course, notes[index].fret)
                        self.orderPosition = offset + i
                    }
                    passStart += passLength
                    pass += 1
                } while looping && !Task.isCancelled
                try? await clock.sleep(until: t0 + .seconds(passStart))
                guard !Task.isCancelled else { return }
                self?.resumeIndex = nil
                self?.finishPlayback(keepNote: false)
            }
            _ = cycleLength
        } catch {
            app.show("Звук недоступен")
        }
    }

    /// Screen toast (canvas «Гриф — позиция пересчитана»).
    private(set) var toast: String?
    private var toastTask: Task<Void, Never>?

    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.4))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    // MARK: Chords (FB-17, FB-23)

    /// Strings sounding after a chord tap (the neck lights them for a moment).
    private(set) var strumming: Set<Int> = []
    /// Strings of the last stroke, low to high (the neck lights them in this order, 12 ms apart).
    private(set) var strumOrder: [Int] = []
    private var strumTask: Task<Void, Never>?

    /// Frets on screen: the current position, the custom window, or the whole neck.
    var visibleFrets: ClosedRange<Int> {
        let maxFret = app?.instrument.fretCount ?? 24
        if mode == .progression { return progression.visibleFrets }
        if let p = fromNotePreview {
            let r = p.position.fretRange
            let lo = max(0, r.lowerBound - 1)
            return lo...min(maxFret, max(lo + 9, r.upperBound + 4))
        }
        if let v = chordPreview {
            // The sheet covers the lower half of the neck: the chord stands in the upper half.
            let fretted = v.notes.map(\.fret).filter { $0 > 0 }
            let lo = v.usesOpenStrings ? 0 : max(1, (fretted.min() ?? 1) - 1)
            return lo...min(maxFret, max(lo + 9, (fretted.max() ?? lo) + 5))
        }
        if mode == .chord, let v = currentVoicing {
            let fretted = v.notes.map(\.fret).filter { $0 > 0 }
            let lo = v.usesOpenStrings ? 0 : max(1, (fretted.min() ?? 1) - 1)
            return lo...min(maxFret, max(lo + 4, (fretted.max() ?? lo) + 1))
        }
        switch settings.neckView {
        case .position:
            if let range = currentPosition?.fretRange {
                // With a capo the fret below it stays in view, dimmed (canvas «капо»).
                let capo = app?.instrument.capo ?? 0
                let lo = capo > 0 && range.lowerBound <= capo ? max(1, capo - 1) : max(0, range.lowerBound)
                return lo...max(range.lowerBound, range.upperBound)
            }
            return 0...min(maxFret, 12)
        case .window:
            let end = min(maxFret, settings.windowStart + settings.windowLength - 1)
            return settings.windowStart...max(settings.windowStart, end)
        case .wholeNeck:
            return 0...maxFret
        }
    }

    /// Tap on a chord: select it (or clear without sound) and strum it — one chord tone per string inside the
    /// visible frets, a downstroke 12 ms per string, ringing until the next chord or 2 s (FB-17, FB-23).
    func tapChord(_ index: Int) {
        guard let app, let fretboard, let chord = keyChords[safe: index] else { return }
        if selectedChord == index { selectedChord = nil; return }
        selectedChord = index
        let classes = Set(chord.notes.map(\.pitchClass))
        let range = visibleFrets
        var voicing: [(course: Int, pitch: Pitch)] = []
        // FB-17: a real shape near the position (FB-9), not «the first chord tone on every string».
        if let type = chord.chord {
            let around = range.count > 14 ? 0...12 : max(1, range.lowerBound - 1)...range.upperBound
            let centre = Double(around.lowerBound + around.upperBound) / 2
            let shapes = ChordVoicings.voicings(chord: type, root: chord.root, on: fretboard, limit: 24, within: around)
            let best = shapes.min { a, b in
                func score(_ v: ChordVoicing) -> Double {
                    let fretted = v.notes.filter { $0.fret > 0 }.map { Double($0.fret) }
                    let c = fretted.isEmpty ? centre : fretted.reduce(0, +) / Double(fretted.count)
                    return v.cost * 0.3 + abs(c - centre) * 0.4
                }
                return score(a) < score(b)
            }
            if let best { voicing = best.notes.map { ($0.course, $0.pitch) } }
        }
        if voicing.isEmpty {
            for course in 0..<app.instrument.courses.count {
                let frets = app.instrument.playableFrets(course: course).filter { range.contains($0) }
                if let fret = frets.first(where: { fretboard.pitch(course: course, fret: $0).map { classes.contains($0.pitchClass) } ?? false }),
                   let pitch = fretboard.pitch(course: course, fret: fret) {
                    voicing.append((course, pitch))
                }
            }
        }
        guard !voicing.isEmpty else { return }
        let sequence = voicing.enumerated().map { (i, v) in (frequency: v.pitch.frequency(a4: app.a4), offset: Double(i) * 0.012) }
        do {
            try app.audio.ensurePlayback()
            app.tuner.pauseForPlayback(seconds: 2.15)   // FB-23: the microphone ignores the phone's own sound (+150 ms)
            app.audio.host.stopNotes()                  // the previous chord stops when the next one is struck
            _ = try app.audio.host.playNotes(sequence, start: .now(delay: 0.02), velocity: 0.75, strings: voicing.map(\.course), noteDuration: 2)
        } catch {
            app.show("Звук недоступен")
        }
        strumOrder = voicing.map(\.course)
        strumming = Set(voicing.map(\.course))
        strumTask?.cancel()
        strumTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.strumming = []
        }
    }

    /// «Пауза»: stops the sound and remembers the next note; the heard note stays lit so the place is visible.
    func stopPlayback() {
        let wasPlaying = isPlaying
        playTask?.cancel()
        app?.audio.host.stopNotes()
        if wasPlaying, let position = orderPosition {
            let total = resumeOrderCount
            let next = position + 1
            resumeIndex = next < total ? next : (loop ? 0 : nil)
        }
        finishPlayback(keepNote: resumeIndex != nil)
    }

    private func finishPlayback(keepNote: Bool) {
        isPlaying = false
        orderPosition = nil
        if !keepNote { playingNote = nil }
        if let app, app.metronome.startedByPlayback { app.metronome.stop() }
    }
}

// MARK: Screenshot hooks of the 2026-11-25 canvas (fretboard boards)

extension FretboardController {
    /// Launch arguments of the fretboard boards (`-fretBoard <Board>` and friends). Each part of the feature adds
    /// its own cases here; AppModel calls this once at launch, before `-sheet`.
    func applyDebugArguments(_ arguments: [String]) {
        func value(_ flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        if arguments.contains("-fretTab") { tabView = true }
        // Tab boards (fork «T»): S6/S7/S8Tab — `-fretTabDemo`; Tab* boards — `-fretTabDemoTonic`; FlowNote3Tab —
        // `-fretProgTab`; TabLargeText adds `-fretTabLarge`.
        if arguments.contains("-fretTabDemo") || arguments.contains("-fretTabDemoTonic") {
            tabDemo(lowest: arguments.contains("-fretTabDemo"))
        }
        if arguments.contains("-fretProgTab") { progressionTabDemo() }
        // Sheet boards (fork «S»): `-fretBpm 100` — the tempo of «Проигрывание»; `-progressionsDemo` — three saved
        // progressions of «Прогрессии» (FretProgressionList).
        if let bpm = value("-fretBpm").flatMap(Double.init) { app?.metronome.bpm = bpm }
        if arguments.contains("-progressionsDemo") { progression.injectSavedDemo() }
        // Main boards (fretboard agent): FlowNote1 — `-fretNote 2:5` (course:fret, the A on an 8-string's 6th string);
        // FlowNote3 — `-fretProg` («A · I–V–vi–IV», the first chord, on the neck).
        if let spot = value("-fretNote")?.split(separator: ":").compactMap({ Int($0) }), spot.count == 2 {
            mode = .scale
            noteSpot = NeckSpot(course: spot[0], fret: spot[1])
        }
        if arguments.contains("-leftHanded") { app?.settings.fretboard.leftHanded = true }
        // S8Loupe: `-fretLoupe 3:5` — the loupe held over course:fret.
        if let spot = value("-fretLoupe")?.split(separator: ":").compactMap({ Int($0) }), spot.count == 2 {
            debugScrub = NeckSpot(course: spot[0], fret: spot[1])
        }
        // FretChordTab: «Am7 · баррэ на 5-м» — `-fretVoicing 5` picks the first barre voicing at that fret.
        if let fret = value("-fretVoicing").flatMap(Int.init), let i = voicings.firstIndex(where: { $0.barreFret == fret }) {
            voicingIndex = i
        }
        if arguments.contains("-fretProg") {
            mode = .progression   // first: entering the mode takes the scale's tonic
            progression.templateId = "pop"
            // FlowNote2 → «Показать на грифе»: from A on the 6th string, 5th fret — the hand stays there.
            progression.start(from: NeckSpot(course: max(0, (app?.instrument.courses.count ?? 6) - 6), fret: 5))
        }
    }
}

extension FretboardController {
    /// Screenshot state of the tab boards: the path «4 ноты наискосок», the 10th note sounding (shown only — no sound).
    /// `lowest` — from the lowest scale note of the lowest string (S6/S7/S8Tab), otherwise from the lowest tonic (Tab*).
    func tabDemo(lowest: Bool) {
        mode = .scale
        if lowest, let fretboard {
            pathStart = (0...4).compactMap { f -> NeckSpot? in
                guard let p = fretboard.pitch(course: 0, fret: f), scale.degreeIndex(of: p, tonic: settings.tonic) != nil else { return nil }
                return NeckSpot(course: 0, fret: f)
            }.first
        }
        pathKind = .fourDiagonal
        tabView = true
        if let n = pathNotes[safe: 9] {
            playingNote = (n.course, n.fret)
            isPlaying = true
        }
    }
}
