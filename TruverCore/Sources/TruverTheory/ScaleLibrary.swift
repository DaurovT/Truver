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

/// Built-in scale library, ~40 scales (TH-2). Modes are stored as parent + shift.
public enum ScaleLibrary {
    private typealias T = LocalizedText

    // MARK: Major and its modes

    public static let major = Scale(id: "major", names: T(ru: "Мажор (ионийский)", en: "Major (Ionian)"),
                                    category: .majorModes, labels: "1 2 3 4 5 6 7")
    public static let dorian = Scale.mode(of: major, shift: 1, id: "dorian",
                                          names: T(ru: "Дорийский", en: "Dorian"), characteristic: "6")
    public static let phrygian = Scale.mode(of: major, shift: 2, id: "phrygian",
                                            names: T(ru: "Фригийский", en: "Phrygian"), characteristic: "♭2")
    public static let lydian = Scale.mode(of: major, shift: 3, id: "lydian",
                                          names: T(ru: "Лидийский", en: "Lydian"), characteristic: "♯4")
    public static let mixolydian = Scale.mode(of: major, shift: 4, id: "mixolydian",
                                              names: T(ru: "Миксолидийский", en: "Mixolydian"), characteristic: "♭7")
    public static let naturalMinor = Scale.mode(of: major, shift: 5, id: "aeolian",
                                                names: T(ru: "Натуральный минор (эолийский)", en: "Natural minor (Aeolian)"),
                                                characteristic: "♭6")
    public static let locrian = Scale.mode(of: major, shift: 6, id: "locrian",
                                           names: T(ru: "Локрийский", en: "Locrian"), characteristic: "♭5")

    // MARK: Harmonic minor and its modes

    public static let harmonicMinor = Scale(id: "harmonic-minor", names: T(ru: "Гармонический минор", en: "Harmonic minor"),
                                            category: .harmonicMinorModes, labels: "1 2 ♭3 4 5 ♭6 7", characteristic: "7")
    static let harmonicMinorModes: [Scale] = [
        Scale.mode(of: harmonicMinor, shift: 1, id: "locrian-nat6", names: T(ru: "Локрийский ♮6", en: "Locrian ♮6"), characteristic: "6"),
        Scale.mode(of: harmonicMinor, shift: 2, id: "ionian-sharp5", names: T(ru: "Ионийский ♯5", en: "Ionian ♯5"), characteristic: "♯5"),
        Scale.mode(of: harmonicMinor, shift: 3, id: "dorian-sharp4", names: T(ru: "Дорийский ♯4", en: "Dorian ♯4"), characteristic: "♯4"),
        Scale.mode(of: harmonicMinor, shift: 4, id: "phrygian-dominant", names: T(ru: "Фригийский доминант", en: "Phrygian dominant"), characteristic: "♭2"),
        Scale.mode(of: harmonicMinor, shift: 5, id: "lydian-sharp2", names: T(ru: "Лидийский ♯2", en: "Lydian ♯2"), characteristic: "♯2"),
        Scale.mode(of: harmonicMinor, shift: 6, id: "ultralocrian", names: T(ru: "Ультралокрийский", en: "Ultralocrian"), characteristic: "𝄫7"),
    ]

    // MARK: Melodic minor and its modes

    public static let melodicMinor = Scale(id: "melodic-minor", names: T(ru: "Мелодический минор", en: "Melodic minor"),
                                           category: .melodicMinorModes, labels: "1 2 ♭3 4 5 6 7", characteristic: "7")
    static let melodicMinorModes: [Scale] = [
        Scale.mode(of: melodicMinor, shift: 1, id: "dorian-flat2", names: T(ru: "Дорийский ♭2", en: "Dorian ♭2"), characteristic: "♭2"),
        Scale.mode(of: melodicMinor, shift: 2, id: "lydian-augmented", names: T(ru: "Лидийский увеличенный", en: "Lydian augmented"), characteristic: "♯5"),
        Scale.mode(of: melodicMinor, shift: 3, id: "lydian-dominant", names: T(ru: "Лидийский доминантовый", en: "Lydian dominant"), characteristic: "♯4"),
        Scale.mode(of: melodicMinor, shift: 4, id: "mixolydian-flat6", names: T(ru: "Миксолидийский ♭6", en: "Mixolydian ♭6"), characteristic: "♭6"),
        Scale.mode(of: melodicMinor, shift: 5, id: "locrian-nat2", names: T(ru: "Локрийский ♮2", en: "Locrian ♮2"), characteristic: "2"),
        Scale.mode(of: melodicMinor, shift: 6, id: "altered", names: T(ru: "Альтерированный", en: "Altered"), characteristic: "♭4"),
    ]

    // MARK: Pentatonic and blues (spelling from the parent heptatonic scale, rule 2)

    static let pentatonicAndBlues: [Scale] = [
        Scale(id: "major-pentatonic", names: T(ru: "Мажорная пентатоника", en: "Major pentatonic"),
              category: .pentatonicAndBlues, labels: "1 2 3 5 6"),
        Scale(id: "minor-pentatonic", names: T(ru: "Минорная пентатоника", en: "Minor pentatonic"),
              category: .pentatonicAndBlues, labels: "1 ♭3 4 5 ♭7"),
        Scale(id: "blues", names: T(ru: "Блюзовая", en: "Blues"),
              category: .pentatonicAndBlues, labels: "1 ♭3 4 ♭5 5 ♭7", characteristic: "♭5"),
        Scale(id: "major-blues", names: T(ru: "Мажорная блюзовая", en: "Major blues"),
              category: .pentatonicAndBlues, labels: "1 2 ♭3 3 5 6", characteristic: "♭3"),
    ]

    // MARK: Symmetric

    static let symmetric: [Scale] = [
        Scale(id: "whole-tone", names: T(ru: "Целотонная", en: "Whole tone"),
              category: .symmetric, labels: "1 2 3 ♯4 ♯5 ♯6", spellingRule: .accidentalPreference),
        Scale(id: "diminished-whole-half", names: T(ru: "Уменьшённая (тон-полутон)", en: "Diminished (whole-half)"),
              category: .symmetric, labels: "1 2 ♭3 4 ♭5 ♭6 6 7"),
        Scale(id: "diminished-half-whole", names: T(ru: "Уменьшённая (полутон-тон)", en: "Diminished (half-whole)"),
              category: .symmetric, labels: "1 ♭2 ♯2 3 ♯4 5 6 ♭7"),
        Scale(id: "augmented", names: T(ru: "Увеличенная", en: "Augmented"),
              category: .symmetric, labels: "1 ♯2 3 5 ♯5 7", spellingRule: .accidentalPreference),
        Scale(id: "chromatic", names: T(ru: "Хроматическая", en: "Chromatic"),
              category: .symmetric, labels: "1 ♯1 2 ♯2 3 4 ♯4 5 ♯5 6 ♯6 7", spellingRule: .chromatic),
    ]

    // MARK: Bebop (the added note is spelled in the direction of the scale, rule 4)

    static let bebop: [Scale] = [
        Scale(id: "bebop-dominant", names: T(ru: "Бибоп доминантовый", en: "Bebop dominant"),
              category: .bebop, labels: "1 2 3 4 5 6 ♭7 7"),
        Scale(id: "bebop-major", names: T(ru: "Бибоп мажорный", en: "Bebop major"),
              category: .bebop, labels: "1 2 3 4 5 ♯5 6 7"),
        Scale(id: "bebop-dorian", names: T(ru: "Бибоп дорийский", en: "Bebop dorian"),
              category: .bebop, labels: "1 2 ♭3 3 4 5 6 ♭7"),
    ]

    // MARK: Exotic

    static let exotic: [Scale] = [
        Scale(id: "hungarian-minor", names: T(ru: "Венгерский минор", en: "Hungarian minor"),
              category: .exotic, labels: "1 2 ♭3 ♯4 5 ♭6 7", characteristic: "♯4"),
        Scale(id: "double-harmonic", names: T(ru: "Двойная гармоническая", en: "Double harmonic major"),
              category: .exotic, labels: "1 ♭2 3 4 5 ♭6 7", characteristic: "♭2"),
        Scale(id: "neapolitan-minor", names: T(ru: "Неаполитанский минор", en: "Neapolitan minor"),
              category: .exotic, labels: "1 ♭2 ♭3 4 5 ♭6 7", characteristic: "♭2"),
        Scale(id: "neapolitan-major", names: T(ru: "Неаполитанский мажор", en: "Neapolitan major"),
              category: .exotic, labels: "1 ♭2 ♭3 4 5 6 7", characteristic: "♭2"),
        Scale(id: "hirajoshi", names: T(ru: "Хираджоши", en: "Hirajoshi"),
              category: .exotic, labels: "1 2 ♭3 5 ♭6"),
        Scale(id: "in", names: T(ru: "Ин (мияко-буси)", en: "In (Miyako-bushi)"),
              category: .exotic, labels: "1 ♭2 4 5 ♭6"),
        Scale(id: "persian", names: T(ru: "Персидская", en: "Persian"),
              category: .exotic, labels: "1 ♭2 3 4 ♭5 ♭6 7", characteristic: "♭5"),
        Scale(id: "enigmatic", names: T(ru: "Энигматическая", en: "Enigmatic"),
              category: .exotic, labels: "1 ♭2 3 ♯4 ♯5 ♯6 7", characteristic: "♯6"),
    ]

    /// All built-in scales in display order. Scales with `needsReview` are excluded (TH-9).
    public static let all: [Scale] =
        [major, dorian, phrygian, lydian, mixolydian, naturalMinor, locrian]
        + [harmonicMinor] + harmonicMinorModes
        + [melodicMinor] + melodicMinorModes
        + pentatonicAndBlues + symmetric + bebop + exotic

    public static func scale(id: String) -> Scale? {
        all.first { $0.id == id } ?? UserLibrary.shared.scales.first { $0.id == id }
    }

    /// Built-in scales and then the user's own (TH-8).
    public static var allWithUser: [Scale] { all + UserLibrary.shared.scales }

    /// FB-25 «Гамма от этой ноты»: the mode of `scale` (on `tonic`) that starts on `pitchClass` — the same notes
    /// from a new tonic (G major from B → B Phrygian). Same-family modes first, then any scale with the same notes.
    /// Nil when the note is not in the scale or no library scale has that rotation.
    public static func mode(of scale: Scale, tonic: NoteName, startingOn pitchClass: Int) -> Scale? {
        let pcs = Set(scale.degrees.map { mod(tonic.pitchClass + $0.semitones, 12) })
        guard pcs.contains(mod(pitchClass, 12)) else { return nil }
        let rotated = Set(pcs.map { mod($0 - pitchClass, 12) })
        let matches = allWithUser.filter { candidate in
            Set(candidate.degrees.map { mod($0.semitones, 12) }) == rotated && !candidate.needsReview
        }
        return matches.first { $0.category == scale.category } ?? matches.first
    }

    public static func scales(in category: ScaleCategory) -> [Scale] { allWithUser.filter { $0.category == category } }

    /// Case-insensitive search by Russian or English name.
    public static func search(_ query: String) -> [Scale] {
        let q = query.trimmedSpaces.lowercased()
        guard !q.isEmpty else { return allWithUser }
        return allWithUser.filter { $0.names.ru.lowercased().contains(q) || $0.names.en.lowercased().contains(q) }
    }
}
