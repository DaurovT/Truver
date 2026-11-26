import Foundation
import Observation
import TruverAudio
import TruverTheory

/// A progression the user saved under a name.
struct SavedProgression: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var key: NoteName
    var chords: [ProgressionChord]
    /// «♩=92» in «Мои прогрессии»: the tempo it was saved with.
    var bpm: Int?
    /// Subtitle in «Мои прогрессии» («поп», «рок-баллада»); nil — the number of chords.
    var note: String?
}

/// «Прогрессия» (FB-11, FB-22, FB-24): a progression from the library in a key, voiced with voice leading over the
/// whole neck or inside a hand window around a chosen note; the ribbon shows the chords, the neck the current chord
/// and the next one faintly; playback strums on the metronome's tempo with a count-in and loops.
@MainActor
@Observable
final class ProgressionController {
    weak var app: AppModel?

    var templateId: String = UserDefaults.standard.string(forKey: "pr.template") ?? "pop" {
        didSet {
            UserDefaults.standard.set(templateId, forKey: "pr.template")
            activeSavedId = nil
            custom = nil
            recompute()
        }
    }
    /// The user's own progression (chords replaced, added or removed); nil = the template as is.
    private(set) var custom: [ProgressionChord]? = {
        guard let data = UserDefaults.standard.data(forKey: "pr.custom") else { return nil }
        return try? JSONDecoder().decode([ProgressionChord].self, from: data)
    }() {
        didSet {
            if let custom, let data = try? JSONEncoder().encode(custom) { UserDefaults.standard.set(data, forKey: "pr.custom") }
            else { UserDefaults.standard.removeObject(forKey: "pr.custom") }
        }
    }
    /// «Мои прогрессии»: kept by name; the open one follows every edit.
    private(set) var saved: [SavedProgression] = {
        guard let data = UserDefaults.standard.data(forKey: "pr.saved") else { return [] }
        return (try? JSONDecoder().decode([SavedProgression].self, from: data)) ?? []
    }() {
        didSet { if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: "pr.saved") } }
    }
    private(set) var activeSavedId: UUID?
    var activeSaved: SavedProgression? { saved.first { $0.id == activeSavedId } }
    /// The bar's beat while playing (0-based), for the dots on the current chord.
    private(set) var playingBeat: Int?
    private var beatTask: Task<Void, Never>?

    /// Voicings the user picked for single chords (index → voicing); cleared when the chords change.
    private var overrides: [Int: ChordVoicing] = [:]
    /// Neck labels: note names or degrees of the chord.
    var showsDegrees = UserDefaults.standard.bool(forKey: "pr.degrees") {
        didSet { UserDefaults.standard.set(showsDegrees, forKey: "pr.degrees") }
    }
    var key = NoteName(.e) {
        didSet {
            overrides = [:]
            if let i = saved.firstIndex(where: { $0.id == activeSavedId }) { saved[i].key = key }
            recompute()
        }
    }
    /// FB-22 «Прогрессия отсюда»: the first chord's lowest note, and the window's lowest fret (nil = whole neck).
    private(set) var anchor: NeckSpot?
    private(set) var windowStart: Int?

    // «Ритм» sheet (FB-24).
    /// nil = each chord's own bars (the 12-bar blues keeps its form).
    var barsPerChord: Int? = UserDefaults.standard.object(forKey: "pr.bars") as? Int {
        didSet { UserDefaults.standard.set(barsPerChord, forKey: "pr.bars") }
    }
    var rhythm: StrumRhythm = StrumRhythm(rawValue: UserDefaults.standard.string(forKey: "pr.rhythm") ?? "") ?? .perBar {
        didSet { UserDefaults.standard.set(rhythm.rawValue, forKey: "pr.rhythm") }
    }
    var loop: Bool = UserDefaults.standard.object(forKey: "pr.loop") as? Bool ?? true {
        didSet { UserDefaults.standard.set(loop, forKey: "pr.loop") }
    }
    /// Metronome click with a bar of count-in. Off by default (user: «нажимаю сыграть — метроном включается»);
    /// a metronome that already plays is followed from its next bar either way.
    var click: Bool = UserDefaults.standard.bool(forKey: "pr.click") {
        didSet { UserDefaults.standard.set(click, forKey: "pr.click") }
    }

    private(set) var voiced: [VoicedChord] = []
    /// The chord shown (selected, or sounding while playing).
    var current = 0
    private(set) var isPlaying = false
    private var playTask: Task<Void, Never>?

    var templates: [Progression] { ProgressionLibrary.all(key: key) }
    var template: Progression { templates.first { $0.id == templateId } ?? templates[0] }
    var progression: Progression {
        guard let custom else { return template }
        return Progression(id: "custom", name: activeSaved?.name ?? "Своя · по «\(template.name)»", key: key, chords: custom)
    }
    var isCustom: Bool { custom != nil }

    /// «G мажор» / «G минор»: by the first chord of the progression.
    var isMinor: Bool {
        ["m", "m7", "m7b5", "mmaj7", "m6", "m9", "m11", "madd9", "dim", "dim7"].contains(progression.chords.first?.chordId ?? "")
    }

    /// Entering from «Гамма»: the scale's tonic and a progression that fits its mode (an edited one stays).
    func syncFromScale(_ scale: Scale, tonic: NoteName) {
        guard custom == nil, activeSavedId == nil else { return }
        let semitones = Set(scale.degrees.map { (($0.semitones % 12) + 12) % 12 })
        let minorThird = semitones.contains(3) && !semitones.contains(4)
        if semitones.contains(1) && !semitones.contains(2) {
            if templateId != "phrygian" { templateId = "phrygian" }
        } else if minorThird != isMinor {
            templateId = minorThird ? "aeolian" : "pop"
        }
        key = tonic
    }

    // MARK: Editing

    private func edit(_ change: (inout [ProgressionChord]) -> Void) {
        var chords = progression.chords
        change(&chords)
        guard !chords.isEmpty else { return }
        custom = chords
        overrides = [:]
        if let i = saved.firstIndex(where: { $0.id == activeSavedId }) { saved[i].chords = chords }
        recompute()
    }

    func insertChord(_ chord: ProgressionChord, at index: Int) {
        edit { $0.insert(chord, at: min(max(0, index), $0.count)) }
        current = min(max(0, index), progression.chords.count - 1)
        if let v = voiced[safe: current]?.voicing, !isPlaying { app?.fretboard.playVoicing(v) }
    }

    /// Moves a chord to another place in the ribbon; the shown chord stays the moved one.
    func moveChord(from: Int, to: Int) {
        let count = progression.chords.count
        guard from != to, (0..<count).contains(from), (0..<count).contains(to) else { return }
        edit { chords in
            let c = chords.remove(at: from)
            chords.insert(c, at: to)
        }
        current = to
    }

    // MARK: My progressions

    func saveAs(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var item = SavedProgression(name: trimmed, key: key, chords: progression.chords)
        item.bpm = app.map { Int($0.metronome.bpm) }
        saved.append(item)
        custom = item.chords
        activeSavedId = item.id
    }

    func renameActive(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let i = saved.firstIndex(where: { $0.id == activeSavedId }) else { return }
        saved[i].name = trimmed
    }

    func open(_ item: SavedProgression) {
        activeSavedId = item.id
        custom = item.chords
        overrides = [:]
        current = 0
        anchor = nil
        windowStart = nil
        if key != item.key { key = item.key } else { recompute() }
    }

    /// «Прогрессия от A» / «Новая прогрессия»: these chords in this key, as the user's own progression.
    func useChords(_ chords: [ProgressionChord], key newKey: NoteName) {
        activeSavedId = nil
        custom = chords
        overrides = [:]
        current = 0
        if key != newKey { key = newKey } else { recompute() }
    }

    /// Debug `-progressionsDemo`: the three saved progressions of the canvas «Прогрессии».
    func injectSavedDemo() {
        func make(_ name: String, _ key: NoteName, _ numerals: String, bpm: Int, note: String?) -> SavedProgression {
            SavedProgression(name: name, key: key, chords: numerals.split(separator: " ").compactMap { ProgressionChord(numeral: String($0)) },
                             bpm: bpm, note: note)
        }
        saved = [make("A · I–V–vi–IV", NoteName(.a), "I V vi IV", bpm: 92, note: "поп · 4 аккорда"),
                 make("Am · i–VI–III–VII", NoteName(.a), "i ♭VI ♭III ♭VII", bpm: 70, note: "рок-баллада"),
                 make("Блюз в E · 12 тактов", NoteName(.e), "I7 I7 I7 I7 IV7 IV7 I7 I7 V7 IV7 I7 V7", bpm: 110, note: "I–IV–V")]
        open(saved[0])
    }

    func deleteActive() {
        guard let id = activeSavedId else { return }
        saved.removeAll { $0.id == id }
        activeSavedId = nil
        custom = nil
        overrides = [:]
        recompute()
    }

    func replaceChord(at index: Int, with chord: ProgressionChord) {
        edit { $0[index] = ProgressionChord(degree: chord.degree, accidental: chord.accidental, chordId: chord.chordId, bars: $0[index].bars) }
        if let v = voiced[safe: index]?.voicing, !isPlaying { app?.fretboard.playVoicing(v) }
    }

    func addChord(_ chord: ProgressionChord) {
        edit { $0.append(chord) }
        current = progression.chords.count - 1
        if let v = voiced[safe: current]?.voicing, !isPlaying { app?.fretboard.playVoicing(v) }
    }

    func removeChord(at index: Int) {
        guard progression.chords.count > 1 else { return }
        edit { $0.remove(at: index) }
        current = min(current, progression.chords.count - 1)
    }

    func setBars(at index: Int, _ bars: Int) {
        edit { $0[index].bars = max(1, min(8, bars)) }
    }

    func resetToTemplate() {
        activeSavedId = nil
        custom = nil
        overrides = [:]
        recompute()
    }

    /// Other voicings of one chord (inside the window when there is one), most comfortable first.
    func alternatives(at index: Int) -> [ChordVoicing] {
        guard let app, let fb = app.fretboard.fretboard, let v = voiced[safe: index] else { return [] }
        let all = ChordVoicings.voicings(chord: v.chord, root: v.root, on: fb, limit: 40)
        var list: [ChordVoicing]
        if let window {
            let inside = all.filter { n in n.notes.allSatisfy { $0.fret == 0 || window.contains($0.fret) } }
            list = Array((inside.isEmpty ? all : inside).prefix(16))
        } else {
            list = Array(all.prefix(16))
        }
        // The one on the neck now comes first, so it is always visible and marked.
        if let shown = v.voicing {
            list.removeAll { $0 == shown }
            list.insert(shown, at: 0)
        }
        return list
    }

    func chooseVoicing(_ voicing: ChordVoicing, at index: Int) {
        guard voiced.indices.contains(index) else { return }
        overrides[index] = voicing
        voiced[index].voicing = voicing
        voiced[index].outOfWindow = false
        current = index
        if !isPlaying { app?.fretboard.playVoicing(voicing) }
    }

    /// Chords to add or put in place (in this key): the key's triads and sevenths, borrowed and secondary chords.
    static let palette: [(title: String, numerals: [String])] = [
        ("Аккорды тональности", ["I", "ii", "iii", "IV", "V", "vi", "vii°"]),
        ("Септаккорды", ["Imaj7", "ii7", "iii7", "IVmaj7", "V7", "vi7", "viiø7"]),
        ("Из минора и заимствованные", ["i", "♭II", "♭III", "iv", "v", "♭VI", "♭VII"]),
        ("Доминанты к ступеням и другие", ["I7", "II7", "III7", "VI7", "VII7", "Isus4", "I5", "V5"]),
    ]

    var window: ClosedRange<Int>? {
        guard let start = windowStart, let app else { return nil }
        return start...min(app.instrument.fretCount, start + 4)
    }

    // MARK: Building

    /// Strings, tuning and frets the voicings were found for: re-voice only when they change.
    private var boardSignature: [Double] = []

    private func signature() -> [Double] {
        guard let app else { return [] }
        return app.tuning.openCents.flatMap { $0 } + [Double(app.instrument.fretCount), Double(app.instrument.capo)]
    }

    func instrumentMayHaveChanged() {
        guard !voiced.isEmpty, signature() != boardSignature else { return }
        anchor = nil
        if let start = windowStart, let app { windowStart = min(start, max(1, app.instrument.fretCount - 4)) }
        recompute()
    }

    func recompute() {
        guard let app, let fretboard = app.fretboard.fretboard else { voiced = []; return }
        boardSignature = signature()
        if isPlaying { stop() }
        voiced = ProgressionVoicer.voice(progression.symbols, on: fretboard, window: window,
                                         anchor: anchor.map { ($0.course, $0.fret) }, loop: loop)
        for (i, v) in overrides where voiced.indices.contains(i) {
            voiced[i].voicing = v
            voiced[i].outOfWindow = false
        }
        current = min(current, max(0, voiced.count - 1))
    }

    /// FB-22: the note becomes the key and the first chord's bass; the hand window is a fret below and three above.
    func start(from spot: NeckSpot) {
        guard let app, let pitch = app.fretboard.fretboard?.pitch(course: spot.course, fret: spot.fret) else { return }
        // The key is the note itself: «i» and «I» are both built on it, so the first chord starts on the pressed note.
        let pc = pitch.pitchClass
        key = NoteName.simpleSpelling(ofPitchClass: pc, preferFlats: [1, 3, 8, 10].contains(pc))
        anchor = spot
        windowStart = ProgressionVoicer.window(around: spot.fret, fretCount: app.instrument.fretCount).lowerBound
        current = 0
        recompute()
        app.fretboard.mode = .progression
    }

    /// «‹ ›» around the window (FB-22): the progression is voiced again.
    func shiftWindow(_ delta: Int) {
        guard let start = windowStart, let app else { return }
        windowStart = min(max(1, start + delta), max(1, app.instrument.fretCount - 4))
        anchor = nil   // the first chord is no longer tied to the original note
        recompute()
    }

    func useWholeNeck() {
        windowStart = nil
        anchor = nil
        recompute()
    }

    /// Key with a simple spelling (TH-7): the progression moves as a whole.
    func transpose(_ semitones: Int) {
        key = progression.transposed(bySemitones: semitones).key
    }

    // MARK: Neck

    /// The current chord full, the next one faint («что дальше», FB-24): only its notes not shared with the current.
    func cells() -> [NeckCell] {
        guard let app, let chord = voiced[safe: current], let v = chord.voicing else { return [] }
        let spelled = chord.chord.spell(root: chord.root)
        func cell(_ n: FretNote, of c: VoicedChord, faint: Bool) -> NeckCell {
            let degree = c.chord.degrees.first { (c.root.pitchClass + $0.semitones) % 12 == n.pitch.pitchClass }
            let role: DegreeRole = n.pitch.pitchClass == c.root.pitchClass ? .tonic
                : ((degree.map { [3, 5].contains($0.label.number) } ?? false) ? .chordTone : .other)
            let names = c.chord.spell(root: c.root)
            let name = names.first { $0.pitchClass == n.pitch.pitchClass }.map { app.formatter.string($0) } ?? app.chromaticName(n.pitch)
            let label = showsDegrees ? (degree?.label.description ?? "") : name
            return NeckCell(course: n.course, fret: n.fret, pitch: n.pitch, label: faint ? "" : label, role: role,
                            emphasis: faint ? .faint : .full, isAdded: false, isPlaying: false)
        }
        _ = spelled
        var result = v.notes.map { cell($0, of: chord, faint: false) }
        let nextIndex = current + 1 < voiced.count ? current + 1 : (loop ? 0 : nil)
        if let nextIndex, nextIndex != current, let next = voiced[safe: nextIndex], let nv = next.voicing {
            let taken = Set(v.notes.map { NeckSpot(course: $0.course, fret: $0.fret) })
            result += nv.notes.filter { !taken.contains(NeckSpot(course: $0.course, fret: $0.fret)) }.map { cell($0, of: next, faint: true) }
        }
        return result
    }

    /// Frets on screen: the window, or the span of the current and next chords with a fret of air.
    var visibleFrets: ClosedRange<Int> {
        let maxFret = app?.instrument.fretCount ?? 24
        if let window { return max(0, window.lowerBound - 1)...window.upperBound }
        let shown = [voiced[safe: current], voiced[safe: (current + 1) % max(1, voiced.count)]].compactMap { $0?.voicing }
        let fretted = shown.flatMap { $0.notes.map(\.fret) }.filter { $0 > 0 }
        let open = shown.contains { $0.usesOpenStrings }
        let lo = open ? 0 : max(1, (fretted.min() ?? 1) - 1)
        return lo...min(maxFret, max(lo + 4, (fretted.max() ?? lo) + 1))
    }

    /// Strings that do not sound in the current chord («×»).
    var mutedCourses: Set<Int> {
        guard let v = voiced[safe: current]?.voicing else { return [] }
        return Set(v.frets.indices.filter { v.frets[$0] == nil })
    }

    // MARK: Sound

    /// Tap on a chord in the ribbon: show it and strum it (FB-23).
    func select(_ index: Int) {
        guard voiced.indices.contains(index) else { return }
        current = index
        if !isPlaying, let v = voiced[index].voicing { app?.fretboard.playVoicing(v) }
    }

    func toggle() { isPlaying ? stop() : play() }

    /// FB-24: count-in a bar (unless the metronome already plays — then from its next bar), the strokes of the
    /// rhythm on the metronome's tempo, the current chord follows the sound; with «По кругу» the next pass is
    /// scheduled one pass ahead at an exact sample.
    func play() {
        guard let app, !voiced.isEmpty else { return }
        let meter = app.metronome.meter
        let wasPlaying = app.metronome.isPlaying
        let startsClick = !wasPlaying && click
        if startsClick { app.metronome.start(byPlayback: true) }
        let bars = progression.chords.map(\.bars)
        let timeline = ProgressionSchedule.build(voiced, chordBars: bars, barsPerChord: barsPerChord, beatsPerBar: meter.numerator,
                                                 bpm: meter.bpm, rhythm: rhythm, countInBars: startsClick ? 1 : 0)
        func notes(_ t: ProgressionTimeline, shift: Double) -> (seq: [(frequency: Double, offset: TimeInterval)], strings: [Int]) {
            var seq: [(frequency: Double, offset: TimeInterval)] = []
            var strings: [Int] = []
            for e in t.events {
                for (n, offset) in zip(e.notes, e.offsets) {
                    seq.append((n.pitch.frequency(a4: app.a4), e.time - t.countIn + shift + offset))
                    strings.append(n.course)
                }
            }
            return (seq, strings)
        }
        do {
            try app.audio.ensurePlayback()
            let first = notes(timeline, shift: timeline.countIn)
            // With the metronome running (or just started for the count-in) — from its next bar; alone — at once.
            let start: AudioEngineHost.NoteStart = app.metronome.isPlaying ? .nextBar(fallbackDelay: 0.1) : .now(delay: 0.1)
            let lead = try app.audio.host.playNotes(first.seq, start: start, velocity: 0.75, strings: first.strings)
            let firstSample = app.audio.host.lastNotesStartSample
            let rate = app.audio.host.noteSampleRate
            let looping = loop
            isPlaying = true
            current = 0
            // The beat of the bar, on the current chord's card (with or without the click).
            let beatLength = 60 / meter.bpm
            let beatsInBar = max(1, meter.numerator)
            beatTask?.cancel()
            beatTask = Task { [weak self] in
                let clock = ContinuousClock()
                let start = clock.now + .seconds(lead)
                var k = 0
                while !Task.isCancelled {
                    try? await clock.sleep(until: start + .seconds(Double(k) * beatLength))
                    guard let self, !Task.isCancelled else { return }
                    self.playingBeat = k % beatsInBar
                    k += 1
                }
            }
            playTask?.cancel()
            playTask = Task { [weak self] in
                let clock = ContinuousClock()
                let t0 = clock.now + .seconds(lead)
                var pass = 0
                repeat {
                    if looping {
                        let next = firstSample + Int64((timeline.countIn + Double(pass + 1) * timeline.cycle) * rate)
                        let again = notes(timeline, shift: 0)
                        _ = try? self?.app?.audio.host.playNotes(again.seq, start: .sample(next), velocity: 0.75, strings: again.strings)
                    }
                    for (i, start) in timeline.chordStarts.enumerated() {
                        try? await clock.sleep(until: t0 + .seconds(start + Double(pass) * timeline.cycle))
                        guard let self, !Task.isCancelled else { return }
                        self.current = i
                    }
                    try? await clock.sleep(until: t0 + .seconds(timeline.countIn + Double(pass + 1) * timeline.cycle))
                    pass += 1
                } while looping && !Task.isCancelled
                guard !Task.isCancelled else { return }
                self?.finish()
            }
        } catch {
            app.show("Звук недоступен")
            if startsClick { app.metronome.stop() }
        }
    }

    func stop() {
        playTask?.cancel()
        app?.audio.host.stopNotes()
        finish()
    }

    private func finish() {
        beatTask?.cancel()
        playingBeat = nil
        isPlaying = false
        if let app, app.metronome.startedByPlayback { app.metronome.stop() }
    }
}
