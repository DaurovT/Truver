import SwiftUI
import TruverTheory

/// TH-8 «Своя гамма»: name, 12 semitone toggles from the current tonic (degree + note), the built-in scale with
/// the same notes if there is one, «Прослушать», save / delete. Opened from «Гамма → Мои» and, prefilled with
/// the neck edits, from «Сохранить как свою».
struct ScaleBuilderSheet: View {
    @Environment(AppModel.self) private var app
    let editingId: String?
    @State private var name = ""
    @State private var steps: Set<Int> = [0]
    @State private var loaded = false

    private var tonic: NoteName { app.fretboard.settings.tonic }
    private var draft: Scale { Scale.user(id: editingId ?? "user-scale-" + UUID().uuidString.prefix(8).lowercased(), name: resolvedName, semitones: Array(steps)) }
    private var resolvedName: String {
        let t = name.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Моя гамма \(app.settings.customScales.count + 1)" : t
    }
    private var twin: Scale? { ScaleLibrary.all.first { $0.semitoneSet == steps.sorted() && !$0.needsReview } }

    var body: some View {
        DesignSheet(title: editingId == nil ? "Своя гамма" : "Изменить гамму", height: 700, close: { app.sheet = .fretScale }) {
            VStack(alignment: .leading, spacing: 14) {
                NameField(prompt: "Моя гамма \(app.settings.customScales.count + 1)", text: $name)
                VStack(alignment: .leading, spacing: 6) {
                    SectionCaption(text: "Ступени от \(app.formatter.string(tonic)) · \(steps.count) \(Self.notes(steps.count))")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                        ForEach(0..<12, id: \.self) { semis in
                            let on = steps.contains(semis)
                            let label = draftLabel(semis)
                            let note = NoteName.spelling(letter: tonic.letter.advanced(by: label.letterSteps), pitchClass: tonic.pitchClass + semis)
                            Button {
                                guard semis != 0 else { return }
                                if on { steps.remove(semis) } else { steps.insert(semis) }
                            } label: {
                                VStack(spacing: 2) {
                                    Typo.notes(label.description, size: 15, weight: .semibold)
                                        .foregroundStyle(on ? Theme.textPrimary : Theme.textMuted)
                                    Typo.notes(app.formatter.string(note), size: 11).foregroundStyle(Theme.textTertiary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? Theme.textPrimary.opacity(0.12) : Color.white.opacity(0.04)))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? Theme.textPrimary.opacity(0.7) : Theme.hairline, lineWidth: 1))
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityLabel("\(label.description), \(app.formatter.string(note))")
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                }
                if let twin {
                    Text("Те же ноты, что у «\(twin.names.ru)»").font(Typo.caption).foregroundStyle(Theme.textSecondary)
                }
                HStack(spacing: 8) {
                    Button { play() } label: { Chip(text: "▶ Прослушать", style: .muted) }.buttonStyle(PressableStyle())
                    if editingId != nil {
                        Button { delete() } label: { Chip(text: "Удалить", style: .muted) }.buttonStyle(PressableStyle())
                    }
                }
            }
        } footer: {
            SheetButton(title: "Сохранить и показать") { save() }
                .disabled(steps.count < 3).opacity(steps.count < 3 ? 0.4 : 1)
        }
        .onAppear(perform: load)
    }

    private func draftLabel(_ semis: Int) -> DegreeLabel {
        let scale = Scale.user(id: "draft", name: "", semitones: Array(steps.union([semis])))
        return scale.degrees.first { $0.semitones % 12 == semis }?.label ?? DegreeLabel.common(semitones: semis)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let id = editingId, let s = app.settings.customScales.first(where: { $0.id == id }) {
            name = s.names.ru
            steps = Set(s.semitoneSet)
        } else {
            steps = Set(app.fretboard.editedSemitones)
        }
    }

    private func play() {
        let base = Pitch(midi: Double(48 + tonic.pitchClass)).cents
        let notes = (steps.sorted() + [12]).enumerated().map { i, s in
            (frequency: Pitch(cents: base + Double(s) * 100).frequency(a4: app.a4), offset: Double(i) * 0.22)
        }
        try? app.audio.ensurePlayback()
        _ = try? app.audio.host.playNotes(notes)
    }

    private func save() {
        let scale = draft
        var list = app.settings.customScales
        if let i = list.firstIndex(where: { $0.id == scale.id }) { list[i] = scale } else { list.append(scale) }
        app.settings.customScales = list
        app.fretboard.setScale(scale.id)
        app.sheet = nil
    }

    private func delete() {
        guard let id = editingId else { return }
        app.settings.customScales.removeAll { $0.id == id }
        if app.fretboard.settings.scaleId == id { app.fretboard.setScale("major") }
        app.sheet = .fretScale
    }

    static func notes(_ n: Int) -> String { ModeParamsSheet.plural(n, "нота", "ноты", "нот") }
}

/// TH-8 «Свой аккорд»: degree toggles (♭3 3 4 … ♯11 13), symbol written after the root, the built-in chord with
/// the same notes, «Прослушать», save / delete. Opened from the chord library («+ Свой»).
struct ChordBuilderSheet: View {
    @Environment(AppModel.self) private var app
    let editingId: String?
    @State private var symbol = ""
    @State private var degrees: Set<DegreeLabel> = [DegreeLabel(3), DegreeLabel(5)]
    @State private var loaded = false

    static let choices: [[DegreeLabel]] = [
        [DegreeLabel(2), DegreeLabel(3, -1), DegreeLabel(3), DegreeLabel(4)],
        [DegreeLabel(5, -1), DegreeLabel(5), DegreeLabel(5, 1), DegreeLabel(6)],
        [DegreeLabel(7, -2), DegreeLabel(7, -1), DegreeLabel(7), DegreeLabel(9, -1)],
        [DegreeLabel(9), DegreeLabel(9, 1), DegreeLabel(11), DegreeLabel(11, 1)],
        [DegreeLabel(13, -1), DegreeLabel(13)],
    ]

    private var root: NoteName { app.fretboard.chordRoot }
    private var resolvedSymbol: String {
        let t = symbol.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? autoSymbol : t
    }
    /// «(1 3 5 ♯11)» when the user wrote nothing.
    private var autoSymbol: String { "(" + sorted.map(\.description).joined(separator: " ") + ")" }
    private var sorted: [DegreeLabel] { Chord.user(id: "draft", name: "", symbol: "", labels: Array(degrees)).degrees.map(\.label) }
    private var draft: Chord {
        Chord.user(id: editingId ?? "user-chord-" + UUID().uuidString.prefix(8).lowercased(), name: resolvedSymbol,
                   symbol: resolvedSymbol, labels: Array(degrees))
    }
    private var twin: Chord? {
        let set = draft.intervalSet
        return ChordLibrary.full.first { !$0.isUserDefined && $0.intervalSet == set }
    }

    var body: some View {
        DesignSheet(title: editingId == nil ? "Свой аккорд" : "Изменить аккорд", height: 700, close: { app.sheet = nil }) {
            VStack(alignment: .leading, spacing: 14) {
                NameField(prompt: "Обозначение, например maj7♯11no3", text: $symbol)
                VStack(alignment: .leading, spacing: 6) {
                    SectionCaption(text: "Ступени от \(app.formatter.string(root)) · 1 всегда звучит")
                    VStack(spacing: 6) {
                        ForEach(Array(Self.choices.enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 6) {
                                ForEach(row, id: \.self) { label in degreeButton(label) }
                                ForEach(0..<(4 - row.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, minHeight: 52) }
                            }
                        }
                    }
                }
                Typo.notes(app.formatter.string(root) + resolvedSymbol + " · "
                           + draft.spell(root: root).map { app.formatter.string($0) }.joined(separator: " "), size: 15, weight: .medium)
                    .foregroundStyle(Theme.textPrimary)
                if let twin {
                    Typo.notes("Уже есть в библиотеке: \(app.formatter.string(root))\(twin.symbol) · \(twin.names.ru)", size: 12).foregroundStyle(Theme.textSecondary)
                }
                HStack(spacing: 8) {
                    Button { play() } label: { Chip(text: "▶ Прослушать", style: .muted) }.buttonStyle(PressableStyle())
                    if editingId != nil {
                        Button { delete() } label: { Chip(text: "Удалить", style: .muted) }.buttonStyle(PressableStyle())
                    }
                }
            }
        } footer: {
            SheetButton(title: "Сохранить и показать") { save() }
                .disabled(degrees.count < 2).opacity(degrees.count < 2 ? 0.4 : 1)
        }
        .onAppear(perform: load)
    }

    private func degreeButton(_ label: DegreeLabel) -> some View {
        let on = degrees.contains(label)
        let note = NoteName.spelling(letter: root.letter.advanced(by: label.letterSteps), pitchClass: root.pitchClass + label.semitones)
        return Button {
            if on { degrees.remove(label) } else { degrees.insert(label) }
        } label: {
            VStack(spacing: 2) {
                Typo.notes(label.description, size: 15, weight: .semibold).foregroundStyle(on ? Theme.textPrimary : Theme.textMuted)
                Typo.notes(app.formatter.string(note), size: 11).foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? Theme.textPrimary.opacity(0.12) : Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? Theme.textPrimary.opacity(0.7) : Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(label.description), \(app.formatter.string(note))")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let id = editingId, let c = app.settings.customChords.first(where: { $0.id == id }) {
            symbol = c.symbol
            degrees = Set(c.degrees.map(\.label).filter { $0 != DegreeLabel(1) })
        }
    }

    private func play() {
        let base = Pitch(midi: Double(48 + root.pitchClass)).cents
        let notes = draft.degrees.enumerated().map { i, d in
            (frequency: Pitch(cents: base + d.cents).frequency(a4: app.a4), offset: Double(i) * 0.03)
        }
        try? app.audio.ensurePlayback()
        _ = try? app.audio.host.playNotes(notes)
    }

    private func save() {
        let chord = draft
        var list = app.settings.customChords
        if let i = list.firstIndex(where: { $0.id == chord.id }) { list[i] = chord } else { list.append(chord) }
        app.settings.customChords = list
        app.fretboard.chordId = chord.id
        if app.fretboard.mode != .chord && app.fretboard.mode != .progression { app.fretboard.mode = .chord }
        app.sheet = nil
    }

    private func delete() {
        guard let id = editingId else { return }
        app.settings.customChords.removeAll { $0.id == id }
        if app.fretboard.chordId == id { app.fretboard.chordId = "maj" }
        app.sheet = nil
    }
}

/// A 44 pt text field of the sheets.
struct NameField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        TextField("", text: $text, prompt: Text(prompt).foregroundColor(Theme.textTertiary))
            .font(Typo.inter(15)).foregroundStyle(Theme.textPrimary)
            .autocorrectionDisabled()
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}
