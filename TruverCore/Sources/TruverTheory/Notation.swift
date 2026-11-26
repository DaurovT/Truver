/// Note naming systems (PRD 5.1.4).
public enum NoteNotation: String, CaseIterable, Sendable, Codable {
    /// C D E F G A B, B♭ (default).
    case international
    /// H for B and B for B♭.
    case german
    /// до ре ми фа соль ля си.
    case solfege
}

public enum Language: String, CaseIterable, Sendable, Codable {
    case ru, en
}

/// Localized text for names stored in the core (scales, chords, tunings).
public struct LocalizedText: Hashable, Sendable, Codable {
    public var ru: String
    public var en: String

    public init(ru: String, en: String) {
        self.ru = ru
        self.en = en
    }

    public init(_ both: String) { self.init(ru: both, en: both) }

    public func text(_ language: Language) -> String { language == .ru ? ru : en }
}

/// Renders note names in the user's notation. Octaves are always scientific (A4 = 440 Hz).
public struct NoteFormatter: Sendable {
    public var notation: NoteNotation
    public var language: Language

    public init(notation: NoteNotation = .international, language: Language = .ru) {
        self.notation = notation
        self.language = language
    }

    public func string(_ name: NoteName) -> String {
        switch notation {
        case .international:
            return name.description
        case .german:
            guard name.letter == .b else { return name.description }
            // B♮ → H, B♭ → B, B𝄫 → B♭, B♯ → H♯.
            if name.accidental >= 0 { return "H" + Accidental.symbol(name.accidental) }
            return "B" + Accidental.symbol(name.accidental + 1)
        case .solfege:
            let syllables = language == .ru
                ? ["до", "ре", "ми", "фа", "соль", "ля", "си"]
                : ["Do", "Re", "Mi", "Fa", "Sol", "La", "Si"]
            return syllables[name.letter.rawValue] + Accidental.symbol(name.accidental)
        }
    }

    /// String keys and neck dots (5.1.4): «соль» shortens to «сол», as in tablature.
    public func short(_ name: NoteName) -> String {
        let full = string(name)
        guard notation == .solfege, language == .ru, full.hasPrefix("соль") else { return full }
        return "сол" + full.dropFirst(4)
    }

    /// Point size of the note in the tuner's centre (5.1.4): 96 for 1–2 characters, 72 for 3–4, 60 for 5+.
    public static func dialSize(for text: String) -> Double {
        switch text.count {
        case ...2: return 96
        case 3...4: return 72
        default: return 60
        }
    }

    public func string(_ note: SpelledNote) -> String {
        string(note.name) + String(note.octave)
    }
}
