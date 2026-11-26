#if canImport(Darwin)
import Darwin
#elseif canImport(Android)
import Android
#elseif canImport(Glibc)
import Glibc
#endif

// «Добавить строй» by the canvas (25.11.2026): the library by kind («Все / Drop / Open / Ниже / Альтернативные»),
// the step-by-step generator («Drop / Ниже всё / Open» from the current tuning) and the editor's
// «Сохранить изменения?» («Вы изменили 6-ю струну: E2 → D2. Это уже другой строй — «Drop D»»). Shared by the iOS
// sheets and the Android bridge (`instrument.*`).

/// Kind of a library template — the chips of «Библиотека строев».
public enum TuningCategory: String, CaseIterable, Sendable, Codable {
    /// The instrument's usual standard (only under «Все»). Case order is the section order of «Все»: by popularity.
    case standard
    /// A standard lowered as a whole («Стандарт E♭», «Стандарт D»).
    case lower
    case drop
    case open
    case alternative

    /// Chip and section title.
    public var title: String {
        switch self {
        case .standard: return "Стандарт"
        case .drop: return "Drop"
        case .open: return "Open"
        case .lower: return "Ниже"
        case .alternative: return "Альтернативные"
        }
    }
}

extension TuningTemplate {
    public var category: TuningCategory {
        if id.contains("drop") { return .drop }
        if id.contains("open") || id.hasPrefix("g7-russian") { return .open }
        if id.contains("standard") {
            // The first standard of its type and string count is the usual one; later ones are lowered.
            let first = TuningTemplates.all.first { $0.type == type && $0.courseCount == courseCount && $0.id.contains("standard") }
            return first?.id == id ? .standard : .lower
        }
        return .alternative
    }
}

extension TuningTemplates {
    /// Most played first, per instrument and string count (user decision, 26.11.2026). Ids not listed come last.
    static let popularity: [String] = [
        // Guitar 6 — the user's menu order: standard, tuned down, drop, baritone, open by root, the rest.
        "g6-standard-e", "g6-standard-eb", "g6-standard-d", "g6-standard-c", "g6-standard-cs",
        "g6-drop-d", "g6-drop-cs", "g6-double-drop-d", "g6-drop-c", "g6-drop-b", "g6-drop-as", "g6-drop-a",
        "g6-standard-b", "g6-standard-a",
        "g6-open-c", "g6-open-cm", "g6-open-c6", "g6-open-cmaj7", "g6-open-d", "g6-open-dm", "g6-open-d5",
        "g6-open-d6", "g6-dadgad", "g6-open-e", "g6-open-em", "g6-open-f", "g6-open-g", "g6-open-gm",
        "g6-open-gsus4", "g6-open-g6", "g6-open-a", "g6-open-am", "g6-open-b", "g6-open-dobro-g",
        "g6-lute", "g6-nashville", "g6-csus2", "g6-nst", "g6-all-fourths", "g6-all-fifths", "g6-major-thirds",
        // Guitar 7
        "g7-standard-b", "g7-drop-a", "g7-standard-a", "g7-drop-g", "g7-standard-bb", "g7-drop-gs", "g7-standard-gs",
        "g7-russian", "g7-high-a", "g7-drop-fs", "g7-russian-minor", "g7-all-fourths",
        // Guitar 8 and 9
        "g8-standard-fs", "g8-drop-e", "g8-standard-e", "g8-standard-f", "g8-drop-eb", "g8-drop-d", "g8-all-fourths",
        "g9-standard-cs", "g9-drop-b", "g9-standard-c", "g9-standard-b", "g9-high-a",
        // Bass
        "b4-standard", "b4-drop-d", "b4-standard-eb", "b4-standard-d", "b4-drop-c", "b4-standard-b", "b4-standard-c",
        "b4-drop-cs", "b4-standard-cs", "b4-drop-b", "b4-drop-a", "b4-tenor", "b4-piccolo", "b4-fifths",
        "b5-standard", "b5-drop-a", "b5-standard-bb", "b5-high-c", "b5-standard-a", "b5-drop-g", "b5-standard-fs",
        "b5-drop-gs", "b5-drop-fs",
        "b6-standard", "b6-drop-a", "b6-standard-bb", "b6-standard-a", "b6-standard-fs", "b6-drop-fs", "b6-all-fourths",
        // Others
        "ukulele-standard", "ukulele-low-g", "mandolin-standard",
    ]

    public static func byPopularity(_ list: [TuningTemplate]) -> [TuningTemplate] {
        let rank = Dictionary(uniqueKeysWithValues: popularity.enumerated().map { ($0.element, $0.offset) })
        return list.enumerated().sorted { a, b in
            let ra = rank[a.element.id] ?? Int.max, rb = rank[b.element.id] ?? Int.max
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
    }

    /// «Библиотека строев»: templates for this instrument (type and string count), of one kind or all —
    /// by kind, then by popularity (kinds: standard, lower, drop, open, alternative).
    public static func library(for instrument: Instrument, category: TuningCategory? = nil) -> [TuningTemplate] {
        let list = byPopularity(compatible(with: instrument).filter { category == nil || $0.category == category })
        return TuningCategory.allCases.flatMap { kind in list.filter { $0.category == kind } }
    }

    /// A template of this instrument with the same main pitches (within 1 cent).
    public static func matching(_ pitches: [Pitch], instrument: Instrument) -> TuningTemplate? {
        compatible(with: instrument).first { t in
            t.notes.count == pitches.count && zip(t.notes, pitches).allSatisfy { abs($0.pitch.cents - $1.cents) < 1 }
        }
    }
}

extension Tuning {
    /// Same main pitches (within 1 cent) — «добавлен», «Такой строй уже есть».
    public func hasSamePitches(_ pitches: [Pitch]) -> Bool {
        coursePitches.count == pitches.count && zip(coursePitches, pitches).allSatisfy { abs($0.cents - $1.cents) < 1 }
    }
}

/// «Генератор строя»: Drop, everything lower, Open — always from the current tuning.
public enum TuningRecipe: Sendable, Equatable {
    /// The lowest string down by `lowest` semitones, the others by `rest` (Drop C from Standard E: 4 and 2).
    case drop(lowest: Int, rest: Int)
    /// Every string down by `semitones`.
    case lower(semitones: Int)
    /// An open major chord on `root` (pitch class): each string to the nearest chord tone, a tie goes down.
    case open(root: Int)

    public struct Result: Sendable {
        public var pitches: [Pitch]
        public var notes: [SpelledNote]
        public var name: String
        /// The library template with these pitches, if any.
        public var templateId: String?
        /// «Струны тоньше 0.052 на 6-й могут болтаться — следите за натяжением».
        public var warning: String?
    }

    public func apply(to tuning: Tuning, instrument: Instrument, formatter: NoteFormatter = NoteFormatter()) -> Result {
        let source = tuning.coursePitches
        var pitches = source
        switch self {
        case let .drop(lowest, rest):
            pitches = source.enumerated().map { $0.offset == 0 ? $0.element.transposed(bySemitones: -lowest) : $0.element.transposed(bySemitones: -rest) }
        case let .lower(semitones):
            pitches = source.map { $0.transposed(bySemitones: -semitones) }
        case let .open(root):
            let tones = [root, root + 4, root + 7].map { (($0 % 12) + 12) % 12 }
            pitches = source.map { p in
                let midi = p.nearestMIDI
                let down = (0...6).first { tones.contains(((midi - $0) % 12 + 12) % 12) } ?? 0
                let up = (0...6).first { tones.contains(((midi + $0) % 12 + 12) % 12) } ?? 0
                return Pitch(midi: Double(up < down ? midi + up : midi - down))
            }
        }
        let template = TuningTemplates.matching(pitches, instrument: instrument)
        let notes = template?.notes ?? TuningSpeller.spell(pitches, preference: .auto)
        let name: String
        if let template {
            name = template.names.ru
        } else {
            switch self {
            case .drop: name = "Drop " + formatter.string(notes[0].name)
            case let .lower(semitones):
                let standard = instrument.type.intervalTemplate.map { t in
                    zip(source.dropFirst(), source).map { $0.nearestMIDI - $1.nearestMIDI } == t.intervals(stringCount: source.count)
                } ?? false
                name = standard ? "Стандарт " + formatter.string(notes[0].name)
                                : "\(tuning.name) · на \(Self.tones(semitones)) ниже"
            case let .open(root):
                name = "Open " + formatter.string(NoteName.simpleSpelling(ofPitchClass: root, preferFlats: false))
            }
        }
        return Result(pitches: pitches, notes: notes, name: name, templateId: template?.id,
                      warning: Self.slackWarning(from: source.first, to: pitches.first, instrument: instrument))
    }

    /// «½ тона», «1 тон», «1½ тона», «2 тона».
    public static func tones(_ semitones: Int) -> String {
        let whole = semitones / 2, half = semitones % 2 == 1
        let number = whole == 0 ? "½" : "\(whole)" + (half ? "½" : "")
        let word = whole == 1 && !half ? "тон" : (whole >= 5 ? "тонов" : "тона")
        return "\(number) \(word)"
    }

    /// Gauge of the lowest string for the same feel after lowering it by ≥ 1½ tones: the set gauge (or the usual
    /// one for this instrument) × 2^(Δ/24).
    static func slackWarning(from old: Pitch?, to new: Pitch?, instrument: Instrument) -> String? {
        guard let old, let new else { return nil }
        let delta = old.cents - new.cents
        guard delta >= 300 else { return nil }
        let n = instrument.courses.count
        let usual: Double?
        switch (instrument.type, n) {
        case (.guitar, 6), (.guitarExtendedHigh, 6): usual = 0.046
        case (.guitar, 7), (.guitarExtendedHigh, 7): usual = 0.059
        case (.guitar, 8), (.guitarExtendedHigh, 8): usual = 0.074
        case (.guitar, 9), (.guitarExtendedHigh, 9): usual = 0.090
        case (.bass, 4): usual = 0.105
        case (.bass, 5), (.bass, 6): usual = 0.130
        default: usual = nil
        }
        guard let gauge = instrument.courses.first?.strings.first?.gauge ?? usual else { return nil }
        let thousandths = Int((gauge * pow(2, delta / 2400) * 1000).rounded())
        let text = "0." + String(repeating: "0", count: max(0, 3 - String(thousandths).count)) + String(thousandths)
        return "Струны тоньше \(text) на \(n)-й могут болтаться — следите за натяжением"
    }
}

/// «Сохранить изменения?» of the tuning editor.
public struct TuningChange: Sendable {
    /// «Вы изменили 6-ю струну: E2 → D2. Это уже другой строй — «Drop D».»
    public var message: String
    /// Another library tuning with the edited pitches («Сохранить как «Drop D»»).
    public var match: String?

    public init(original: Tuning, draft: Tuning, instrument: Instrument, formatter: NoteFormatter = NoteFormatter()) {
        let before = original.coursePitches, after = draft.coursePitches
        let changed = before.indices.filter { $0 < after.count && abs(before[$0].cents - after[$0].cents) >= 0.5 }
        let n = before.count
        var text: String
        if changed.count == 1, let c = changed.first {
            let old = original.spelledNotes[c], new = draft.spelledNotes[c]
            text = "Вы изменили \(n - c)-ю струну: \(formatter.string(old)) → \(formatter.string(new))."
        } else if changed.count > 1 {
            let k = changed.count
            let word = k % 10 == 1 && k % 100 != 11 ? "струну" : ((2...4).contains(k % 10) && !(12...14).contains(k % 100) ? "струны" : "струн")
            text = "Вы изменили \(k) \(word)."
        } else {
            text = "Вы изменили строй «\(original.name)»."
        }
        var match: String?
        if !changed.isEmpty, let t = TuningTemplates.matching(after, instrument: instrument), t.names.ru != original.name {
            match = t.names.ru
            text += " Это уже другой строй — «\(t.names.ru)»."
        }
        self.message = text
        self.match = match
    }
}
