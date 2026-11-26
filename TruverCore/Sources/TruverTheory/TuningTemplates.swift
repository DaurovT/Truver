/// A read-only tuning template (PR-4, PRD 5.1.3). Users copy templates into their instrument.
public struct TuningTemplate: Identifiable, Hashable, Sendable {
    public var id: String
    public var type: InstrumentType
    public var names: LocalizedText
    /// Main note of each course, in physical order.
    public var notes: [SpelledNote]
    public var pairing: CoursePairing

    public var courseCount: Int { notes.count }

    init(_ id: String, _ type: InstrumentType, ru: String, en: String, _ notes: String, pairing: CoursePairing = .single) {
        self.id = id
        self.type = type
        self.names = LocalizedText(ru: ru, en: en)
        self.notes = notes.split(separator: " ").map { token in
            guard let note = SpelledNote(parsing: String(token)) else { preconditionFailure("Bad note \(token) in \(id)") }
            return note
        }
        self.pairing = pairing
    }

    /// Open pitches per course and string (the second string of a pair is a unison or an octave above).
    public var openCents: [[Double]] {
        notes.map { note in
            let cents = note.pitch.cents
            switch pairing {
            case .single: return [cents]
            case .unison: return [cents, cents]
            case .octave: return [cents, cents + 1200]
            }
        }
    }

    public func makeTuning(language: Language = .ru) -> Tuning {
        Tuning(name: names.text(language), openCents: openCents,
               accidentalPreference: notes.contains { $0.name.accidental < 0 } ? .flat : .auto,
               isTemplateCopy: true, templateId: id)
    }

    /// A new instrument made from this template (onboarding, "Заменить инструмент", 6.1 п. 19).
    public func makeInstrument(name: String? = nil, language: Language = .ru) -> Instrument {
        let tuning = makeTuning(language: language)
        return Instrument(name: name ?? TuningTemplates.defaultInstrumentName(type: type, courses: courseCount, language: language),
                          type: type,
                          courses: Array(repeating: Course(pairing: pairing), count: courseCount),
                          fretCount: TuningTemplates.defaultFretCount(type, courses: courseCount),
                          tunings: [tuning])
    }
}

public enum TuningTemplates {
    public static let all: [TuningTemplate] = [
        // 6 strings
        .init("g6-standard-e", .guitar, ru: "Стандарт E", en: "Standard E", "E2 A2 D3 G3 B3 E4"),
        .init("g6-drop-d", .guitar, ru: "Drop D", en: "Drop D", "D2 A2 D3 G3 B3 E4"),
        .init("g6-standard-eb", .guitar, ru: "Стандарт E♭", en: "Standard E♭", "E♭2 A♭2 D♭3 G♭3 B♭3 E♭4"),
        .init("g6-standard-d", .guitar, ru: "Стандарт D", en: "Standard D", "D2 G2 C3 F3 A3 D4"),
        .init("g6-drop-c", .guitar, ru: "Drop C", en: "Drop C", "C2 G2 C3 F3 A3 D4"),
        .init("g6-open-g", .guitar, ru: "Open G", en: "Open G", "D2 G2 D3 G3 B3 D4"),
        .init("g6-open-d", .guitar, ru: "Open D", en: "Open D", "D2 A2 D3 F♯3 A3 D4"),
        .init("g6-dadgad", .guitar, ru: "DADGAD", en: "DADGAD", "D2 A2 D3 G3 A3 D4"),
        .init("g6-drop-cs", .guitar, ru: "Drop C♯", en: "Drop C♯", "C♯2 G♯2 C♯3 F♯3 A♯3 D♯4"),
        .init("g6-drop-b", .guitar, ru: "Drop B", en: "Drop B", "B1 F♯2 B2 E3 G♯3 C♯4"),
        .init("g6-drop-a", .guitar, ru: "Drop A", en: "Drop A", "A1 E2 A2 D3 F♯3 B3"),
        .init("g6-standard-cs", .guitar, ru: "Стандарт C♯", en: "Standard C♯", "C♯2 F♯2 B2 E3 G♯3 C♯4"),
        .init("g6-standard-c", .guitar, ru: "Стандарт C", en: "Standard C", "C2 F2 B♭2 E♭3 G3 C4"),
        .init("g6-standard-b", .guitar, ru: "Стандарт B (баритон)", en: "Standard B (baritone)", "B1 E2 A2 D3 F♯3 B3"),
        .init("g6-standard-a", .guitar, ru: "Стандарт A (баритон)", en: "Standard A (baritone)", "A1 D2 G2 C3 E3 A3"),
        .init("g6-drop-as", .guitar, ru: "Drop A♯", en: "Drop A♯", "A♯1 F2 A♯2 D♯3 G3 C4"),
        .init("g6-double-drop-d", .guitar, ru: "Double Drop D", en: "Double Drop D", "D2 A2 D3 G3 B3 D4"),
        .init("g6-open-e", .guitar, ru: "Open E", en: "Open E", "E2 B2 E3 G♯3 B3 E4"),
        .init("g6-open-a", .guitar, ru: "Open A", en: "Open A", "E2 A2 E3 A3 C♯4 E4"),
        .init("g6-open-c", .guitar, ru: "Open C", en: "Open C", "C2 G2 C3 G3 C4 E4"),
        .init("g6-open-f", .guitar, ru: "Open F", en: "Open F", "C2 F2 C3 F3 C4 F4"),
        .init("g6-open-b", .guitar, ru: "Open B", en: "Open B", "B1 F♯2 B2 F♯3 B3 D♯4"),
        .init("g6-open-em", .guitar, ru: "Open Em", en: "Open Em", "E2 B2 E3 G3 B3 E4"),
        .init("g6-open-dm", .guitar, ru: "Open Dm", en: "Open Dm", "D2 A2 D3 F3 A3 D4"),
        .init("g6-open-gm", .guitar, ru: "Open Gm", en: "Open Gm", "D2 G2 D3 G3 B♭3 D4"),
        .init("g6-open-am", .guitar, ru: "Open Am", en: "Open Am", "E2 A2 E3 A3 C4 E4"),
        .init("g6-open-cm", .guitar, ru: "Open Cm", en: "Open Cm", "C2 G2 C3 G3 C4 E♭4"),
        .init("g6-csus2", .guitar, ru: "Csus2", en: "Csus2", "C2 G2 C3 G3 C4 D4"),
        .init("g6-open-c6", .guitar, ru: "Open C6", en: "Open C6", "C2 A2 C3 G3 C4 E4"),
        .init("g6-open-d5", .guitar, ru: "Open D5 (DADDAD)", en: "Open D5 (DADDAD)", "D2 A2 D3 D3 A3 D4"),
        .init("g6-nst", .guitar, ru: "Фрипп (NST)", en: "New Standard Tuning", "C2 G2 D3 A3 E4 G4"),
        .init("g6-all-fourths", .guitar, ru: "По квартам", en: "All fourths", "E2 A2 D3 G3 C4 F4"),
        .init("g6-all-fifths", .guitar, ru: "По квинтам", en: "All fifths", "C2 G2 D3 A3 E4 B4"),
        .init("g6-major-thirds", .guitar, ru: "По большим терциям", en: "Major thirds", "G♯2 C3 E3 G♯3 C4 E4"),
        .init("g6-nashville", .guitar, ru: "Nashville", en: "Nashville", "E3 A3 D4 G4 B3 E4"),
        .init("g6-open-cmaj7", .guitar, ru: "Open CM7", en: "Open CM7", "C2 G2 C3 G3 B3 E4"),
        .init("g6-open-d6", .guitar, ru: "Open D6", en: "Open D6", "D2 A2 D3 F♯3 B3 D4"),
        .init("g6-open-gsus4", .guitar, ru: "Open Gsus4", en: "Open Gsus4", "D2 G2 D3 G3 C4 D4"),
        .init("g6-open-g6", .guitar, ru: "Open G6", en: "Open G6", "D2 G2 D3 G3 B3 E4"),
        .init("g6-open-dobro-g", .guitar, ru: "Dobro Open G", en: "Dobro Open G", "G2 B2 D3 G3 B3 D4"),
        .init("g6-lute", .guitar, ru: "Лютня / виуэла", en: "Lute / vihuela", "E2 A2 D3 F♯3 B3 E4"),
        // 7 strings
        .init("g7-standard-b", .guitar, ru: "Стандарт B", en: "Standard B", "B1 E2 A2 D3 G3 B3 E4"),
        .init("g7-drop-a", .guitar, ru: "Drop A", en: "Drop A", "A1 E2 A2 D3 G3 B3 E4"),
        .init("g7-standard-bb", .guitar, ru: "Стандарт B♭", en: "Standard B♭", "B♭1 E♭2 A♭2 D♭3 G♭3 B♭3 E♭4"),
        .init("g7-standard-a", .guitar, ru: "Стандарт A", en: "Standard A", "A1 D2 G2 C3 F3 A3 D4"),
        .init("g7-drop-g", .guitar, ru: "Drop G", en: "Drop G", "G1 D2 G2 C3 F3 A3 D4"),
        .init("g7-russian", .guitar, ru: "Русская семиструнная (открытый G)", en: "Russian 7-string (open G)", "D2 G2 B2 D3 G3 B3 D4"),
        .init("g7-standard-gs", .guitar, ru: "Стандарт G♯", en: "Standard G♯", "G♯1 C♯2 F♯2 B2 E3 G♯3 C♯4"),
        .init("g7-drop-gs", .guitar, ru: "Drop G♯", en: "Drop G♯", "G♯1 D♯2 G♯2 C♯3 F♯3 A♯3 D♯4"),
        .init("g7-drop-fs", .guitar, ru: "Drop F♯", en: "Drop F♯", "F♯1 C♯2 F♯2 B2 E3 G♯3 C♯4"),
        .init("g7-high-a", .guitar, ru: "High A (джаз)", en: "High A (jazz)", "E2 A2 D3 G3 B3 E4 A4"),
        .init("g7-all-fourths", .guitar, ru: "По квартам", en: "All fourths", "B1 E2 A2 D3 G3 C4 F4"),
        .init("g7-russian-minor", .guitar, ru: "Русская семиструнная (минор)", en: "Russian 7-string (minor)", "D2 G2 B♭2 D3 G3 B♭3 D4"),
        // 8 strings
        .init("g8-standard-fs", .guitar, ru: "Стандарт F♯", en: "Standard F♯", "F♯1 B1 E2 A2 D3 G3 B3 E4"),
        .init("g8-drop-e", .guitar, ru: "Drop E", en: "Drop E", "E1 B1 E2 A2 D3 G3 B3 E4"),
        .init("g8-standard-f", .guitar, ru: "Стандарт F", en: "Standard F", "F1 B♭1 E♭2 A♭2 D♭3 G♭3 B♭3 E♭4"),
        .init("g8-standard-e", .guitar, ru: "Стандарт E", en: "Standard E", "E1 A1 D2 G2 C3 F3 A3 D4"),
        .init("g8-drop-d", .guitar, ru: "Drop D", en: "Drop D", "D1 A1 D2 G2 C3 F3 A3 D4"),
        .init("g8-drop-eb", .guitar, ru: "Drop E♭", en: "Drop E♭", "E♭1 B♭1 E♭2 A♭2 D♭3 G♭3 B♭3 E♭4"),
        .init("g8-all-fourths", .guitar, ru: "По квартам", en: "All fourths", "F♯1 B1 E2 A2 D3 G3 C4 F4"),
        // 9 strings
        .init("g9-standard-cs", .guitar, ru: "Стандарт C♯", en: "Standard C♯", "C♯1 F♯1 B1 E2 A2 D3 G3 B3 E4"),
        .init("g9-drop-b", .guitar, ru: "Drop B", en: "Drop B", "B0 F♯1 B1 E2 A2 D3 G3 B3 E4"),
        .init("g9-standard-c", .guitar, ru: "Стандарт C", en: "Standard C", "C1 F1 B♭1 E♭2 A♭2 D♭3 G♭3 B♭3 E♭4"),
        .init("g9-standard-b", .guitar, ru: "Стандарт B", en: "Standard B", "B0 E1 A1 D2 G2 C3 F3 A3 D4"),
        .init("g9-high-a", .guitarExtendedHigh, ru: "С высокой A", en: "With high A", "F♯1 B1 E2 A2 D3 G3 B3 E4 A4"),
        // Bass
        .init("b4-standard", .bass, ru: "Бас 4: стандарт", en: "Bass 4: standard", "E1 A1 D2 G2"),
        .init("b4-standard-eb", .bass, ru: "Стандарт E♭", en: "Standard E♭", "E♭1 A♭1 D♭2 G♭2"),
        .init("b4-standard-d", .bass, ru: "Стандарт D", en: "Standard D", "D1 G1 C2 F2"),
        .init("b4-standard-cs", .bass, ru: "Стандарт C♯", en: "Standard C♯", "C♯1 F♯1 B1 E2"),
        .init("b4-standard-c", .bass, ru: "Стандарт C", en: "Standard C", "C1 F1 B♭1 E♭2"),
        .init("b4-standard-b", .bass, ru: "Стандарт B (BEAD)", en: "Standard B (BEAD)", "B0 E1 A1 D2"),
        .init("b4-drop-d", .bass, ru: "Drop D", en: "Drop D", "D1 A1 D2 G2"),
        .init("b4-drop-cs", .bass, ru: "Drop C♯", en: "Drop C♯", "C♯1 G♯1 C♯2 F♯2"),
        .init("b4-drop-c", .bass, ru: "Drop C", en: "Drop C", "C1 G1 C2 F2"),
        .init("b4-drop-b", .bass, ru: "Drop B", en: "Drop B", "B0 F♯1 B1 E2"),
        .init("b4-drop-a", .bass, ru: "Drop A", en: "Drop A", "A0 E1 A1 D2"),
        .init("b4-tenor", .bass, ru: "Tenor", en: "Tenor", "A1 D2 G2 C3"),
        .init("b4-piccolo", .bass, ru: "Piccolo", en: "Piccolo", "E2 A2 D3 G3"),
        .init("b4-fifths", .bass, ru: "По квинтам", en: "All fifths", "C1 G1 D2 A2"),
        .init("b5-standard", .bass, ru: "Бас 5: стандарт", en: "Bass 5: standard", "B0 E1 A1 D2 G2"),
        .init("b5-standard-bb", .bass, ru: "Стандарт B♭", en: "Standard B♭", "B♭0 E♭1 A♭1 D♭2 G♭2"),
        .init("b5-standard-a", .bass, ru: "Стандарт A", en: "Standard A", "A0 D1 G1 C2 F2"),
        .init("b5-drop-a", .bass, ru: "Drop A", en: "Drop A", "A0 E1 A1 D2 G2"),
        .init("b5-drop-gs", .bass, ru: "Drop G♯", en: "Drop G♯", "G♯0 D♯1 G♯1 C♯2 F♯2"),
        .init("b5-drop-g", .bass, ru: "Drop G", en: "Drop G", "G0 D1 G1 C2 F2"),
        .init("b5-high-c", .bass, ru: "High C (Tenor)", en: "High C (Tenor)", "E1 A1 D2 G2 C3"),
        .init("b5-standard-fs", .bass, ru: "Стандарт F♯", en: "Standard F♯", "F♯0 B0 E1 A1 D2"),
        .init("b5-drop-fs", .bass, ru: "Drop F♯", en: "Drop F♯", "F♯0 C♯1 F♯1 B1 E2"),
        .init("b6-standard", .bass, ru: "Бас 6: стандарт", en: "Bass 6: standard", "B0 E1 A1 D2 G2 C3"),
        .init("b6-standard-bb", .bass, ru: "Стандарт B♭", en: "Standard B♭", "B♭0 E♭1 A♭1 D♭2 G♭2 B2"),
        .init("b6-standard-a", .bass, ru: "Стандарт A", en: "Standard A", "A0 D1 G1 C2 F2 B♭2"),
        .init("b6-drop-a", .bass, ru: "Drop A", en: "Drop A", "A0 E1 A1 D2 G2 C3"),
        .init("b6-standard-fs", .bass, ru: "Стандарт F♯", en: "Standard F♯", "F♯0 B0 E1 A1 D2 G2"),
        .init("b6-drop-fs", .bass, ru: "Drop F♯", en: "Drop F♯", "F♯0 C♯1 F♯1 B1 E2 A2"),
        .init("b6-all-fourths", .bass, ru: "По квартам (от E)", en: "All fourths (from E)", "E1 A1 D2 G2 C3 F3"),
        // Others
        .init("ukulele-standard", .ukulele, ru: "Стандарт C", en: "Standard C", "G4 C4 E4 A4"),
        .init("ukulele-low-g", .ukulele, ru: "Low G", en: "Low G", "G3 C4 E4 A4"),
        .init("mandolin-standard", .mandolin, ru: "Мандолина: стандарт", en: "Mandolin: standard", "G3 D4 A4 E5", pairing: .unison),
    ]
    // Dutar, tanbur, rubob have no templates in v1 (PRD 5.1.3).

    public static func template(id: String) -> TuningTemplate? { all.first { $0.id == id } }

    /// Library filtered for the current instrument (6.1 п. 19): same type and course count.
    public static func compatible(with instrument: Instrument) -> [TuningTemplate] {
        all.filter { isCompatible($0, with: instrument) }
    }

    public static func isCompatible(_ template: TuningTemplate, with instrument: Instrument) -> Bool {
        template.type == instrument.type && template.courseCount == instrument.courses.count
    }

    /// Guitars (any number of strings) and basses: 24 frets (user decision). Editable in the instrument editor (PR-1).
    public static func defaultFretCount(_ type: InstrumentType, courses: Int) -> Int {
        switch type {
        case .guitar, .guitarExtendedHigh, .bass: return 24
        case .ukulele: return 18
        case .mandolin: return 20
        case .dutar, .tanbur, .rubob: return 17
        }
    }

    static func defaultInstrumentName(type: InstrumentType, courses: Int, language: Language) -> String {
        let ru = language == .ru
        switch type {
        // Canvas: «8-струнная гитара», «5-струнный бас».
        case .guitar, .guitarExtendedHigh: return ru ? "\(courses)-струнная гитара" : "\(courses)-string guitar"
        case .bass: return ru ? "\(courses)-струнный бас" : "\(courses)-string bass"
        case .ukulele: return ru ? "Укулеле" : "Ukulele"
        case .mandolin: return ru ? "Мандолина" : "Mandolin"
        case .dutar: return ru ? "Дутар" : "Dutar"
        case .tanbur: return ru ? "Танбур" : "Tanbur"
        case .rubob: return ru ? "Рубоб" : "Rubab"
        }
    }
}
