import SwiftUI
import TruverTheory

/// «Прогрессия» row under the mode switcher: key «G ▾» (transposes the whole progression, TH-7), the progression
/// «Поп · I–V–vi–IV ▾», and the «Ритм» sheet. No canvas board yet: built from the «Аккорд» row's pieces.
struct ProgressionPickerRow: View {
    @Environment(AppModel.self) private var app
    /// Asks for a name: true — rename the open progression, false — save as new.
    var askName: (Bool) -> Void = { _ in }

    var body: some View {
        let p = app.fretboard.progression
        HStack(spacing: 8) {
            Menu {
                ForEach(0..<12, id: \.self) { pc in
                    let name = NoteName.simpleSpelling(ofPitchClass: pc, preferFlats: [1, 3, 8, 10].contains(pc))
                    Button(app.formatter.string(name)) {
                        p.transpose(((pc - p.key.pitchClass) % 12 + 12) % 12)
                    }
                }
            } label: {
                capsule(app.formatter.string(p.key) + (p.isMinor ? " минор" : " мажор"), width: 116)
            }
            .accessibilityLabel("Тональность \(app.formatter.string(p.key))")
            Menu {
                Button("Сохранить как…") { askName(false) }
                if p.activeSaved != nil {
                    Button("Переименовать…") { askName(true) }
                    Button("Удалить", role: .destructive) { p.deleteActive() }
                } else if p.isCustom {
                    Button("Вернуть «\(p.template.name)»") { p.resetToTemplate() }
                }
                if !p.saved.isEmpty {
                    Section("Мои прогрессии") {
                        ForEach(p.saved) { item in Button(item.name) { p.open(item) } }
                    }
                }
                Section("Шаблоны") {
                    ForEach(p.templates) { t in
                        Button(t.name) { p.templateId = t.id }
                    }
                }
            } label: {
                capsule(p.progression.name, width: nil)
            }
            .accessibilityLabel("Прогрессия: \(p.progression.name)")
            RoundIconButton(icon: .sliders, size: 44, label: "Ритм") { app.sheet = .fretProgression }
        }
    }

    private func capsule(_ text: String, width: CGFloat?) -> some View {
        HStack(spacing: 6) {
            Typo.notes(text, size: 14, weight: .medium).foregroundStyle(Theme.textPrimary).lineLimit(1)
            if width == nil { Spacer(minLength: 0) }
            Icon(.chevronDown, size: 14, color: Theme.textTertiary)
        }
        .padding(.leading, 14).padding(.trailing, 10)
        .frame(width: width, height: 44)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .background(Capsule().fill(Theme.cardFill))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

/// The chord ribbon (FB-24): bar numbers, Roman numeral, chord name; the current chord is lit; «вне позиции» when a
/// chord left the hand window (FB-22). Tap shows the chord and strums it.
struct ProgressionRibbon: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let p = app.fretboard.progression
        let chords = p.progression.chords
        ScrollViewReader { reader in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(Array(p.voiced.enumerated()), id: \.offset) { index, v in
                        let selected = index == p.current
                        let bar = barNumber(index, chords: chords, barsPerChord: p.barsPerChord)
                        // First tap shows and plays the chord; a tap on the shown one opens its editor.
                        Button { if index == p.current && !p.isPlaying { app.sheet = .progressionChord(index) } else { p.select(index) } } label: {
                            RibbonCard(bar: bar, name: compactChordName(v.chord.name(root: v.root, formatter: app.formatter)),
                                       caption: caption(v, numeral: chords[safe: index]?.numeral ?? ""),
                                       warning: v.outOfWindow || v.voicing == nil, missing: v.voicing == nil, selected: selected,
                                       beats: selected && p.isPlaying ? app.metronome.meter.numerator : nil, beat: p.playingBeat)
                        }
                        .buttonStyle(PressableStyle())
                        .id(index)
                        // Hold and drag a chord to another place in the ribbon.
                        .draggable(String(index))
                        .dropDestination(for: String.self) { items, _ in
                            guard let from = items.first.flatMap(Int.init) else { return false }
                            p.moveChord(from: from, to: index)
                            return true
                        }
                        .accessibilityLabel("Такт \(bar), \(v.chord.name(root: v.root, formatter: app.formatter))")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                    Button { app.sheet = .progressionChord(nil) } label: {
                        Icon(.plus, size: 20, color: Theme.textSecondary)
                            .frame(width: 52, height: 64)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairlineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Добавить аккорд")
                }
                .padding(.horizontal, 1)
            }
            .scrollIndicators(.hidden)
            .onChange(of: p.current) { _, index in
                withAnimation(Motion.out(Motion.Duration.base)) { reader.scrollTo(index, anchor: .center) }
            }
        }
        .frame(height: 64)
    }

    private func caption(_ v: VoicedChord, numeral: String) -> String {
        if v.voicing == nil { return "не помещается" }
        return v.outOfWindow ? "вне позиции" : numeral
    }

    private func barNumber(_ index: Int, chords: [ProgressionChord], barsPerChord: Int?) -> Int {
        1 + chords.prefix(index).reduce(0) { $0 + (barsPerChord ?? $1.bars) }
    }
}

/// Window «‹ лады 4–8 ›» (FB-22) or «Весь гриф», and «Сыграть / Стоп».
struct ProgressionControlRow: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let p = app.fretboard.progression
        HStack(spacing: 8) {
            if let window = p.window {
                RoundIconButton(icon: .chevronLeft, size: 44, label: "Окно ниже") { p.shiftWindow(-1) }
                Button { p.useWholeNeck() } label: {
                    VStack(spacing: 0) {
                        Text("Окно руки").font(Typo.inter(12)).foregroundStyle(Theme.textTertiary)
                        Text("лады \(window.lowerBound)–\(window.upperBound)").font(Typo.inter(12, .semibold)).foregroundStyle(Theme.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Тап — весь гриф")
                RoundIconButton(icon: .chevronRight, size: 44, label: "Окно выше") { p.shiftWindow(1) }
            } else {
                // Tempo right here (it is the metronome's): ± 1, long press ± 5.
                HStack(spacing: 6) {
                    tempoButton(.minus, -1)
                    VStack(spacing: 0) {
                        Text("\(Int(app.metronome.displayBPM))").font(Typo.fixed(17, .semibold)).foregroundStyle(Theme.textPrimary).monospacedDigit()
                        Text("BPM").font(Typo.inter(10)).foregroundStyle(Theme.textTertiary)
                    }
                    .frame(minWidth: 40)
                    tempoButton(.plus, 1)
                }
                .frame(maxWidth: .infinity)
            }
            Button { p.toggle() } label: {
                HStack(spacing: 8) {
                    Icon(p.isPlaying ? .stop : .play, size: 18, color: Theme.background)
                    Text(p.isPlaying ? "Стоп" : "Сыграть").font(Typo.inter(16, .semibold)).foregroundStyle(Theme.background)
                }
                .padding(.leading, 14).padding(.trailing, 18)
                .frame(height: 52)
                .background(Capsule().fill(Theme.textPrimary))
                .shadow(color: .black.opacity(0.35), radius: 9, y: 6)
                .fixedSize()
            }
            .buttonStyle(PressableStyle())
            .layoutPriority(1)
            .accessibilityLabel(p.isPlaying ? "Стоп" : "Сыграть прогрессию")
        }
    }
}

extension ProgressionControlRow {
    fileprivate func tempoButton(_ icon: AppIcon, _ delta: Double) -> some View {
        RoundIconButton(icon: icon, size: 40, iconSize: 16, label: delta > 0 ? "Быстрее" : "Медленнее") { app.metronome.step(delta) }
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in app.metronome.step(delta * 5) })
    }
}

/// One chord of the progression (tap on the shown chord, or «+»): its place in the key, another chord from the
/// palette, another voicing, bars, delete. `index` nil = adding a chord at the end.
struct ProgressionChordSheet: View {
    @Environment(AppModel.self) private var app
    let index: Int?
    /// Adding a chord at this place in the ribbon (nil = at the end).
    var insertAt: Int?
    @State private var anyChord = false
    @State private var anyRoot = 0
    @State private var anyType = "maj7"

    private func apply(_ chord: ProgressionChord) {
        let p = app.fretboard.progression
        if let insertAt { p.insertChord(chord, at: insertAt) }
        else if let index { p.replaceChord(at: index, with: chord) }
        else { p.addChord(chord) }
        app.sheet = nil
    }

    var body: some View {
        let p = app.fretboard.progression
        let chord = index.flatMap { p.progression.chords[safe: $0] }
        let voiced = index.flatMap { p.voiced[safe: $0] }
        let title = voiced.map { "Такт \(bar(index!)) · " + compactChordName($0.chord.name(root: $0.root, formatter: app.chordFormatter)) } ?? (insertAt != nil ? "Вставить аккорд" : "Добавить аккорд")
        DesignSheet(title: title, height: 784, close: { app.sheet = nil }) {
            VStack(alignment: .leading, spacing: 16) {
                if insertAt == nil, let index, let chord {
                    let alternatives = p.alternatives(at: index)
                    if !alternatives.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Расположение · \(alternatives.count)").font(Typo.caption).foregroundStyle(Theme.textTertiary)
                            ScrollView(.horizontal) {
                                HStack(spacing: 8) {
                                    ForEach(Array(alternatives.enumerated()), id: \.offset) { _, v in
                                        let selected = voiced?.voicing == v
                                        Button { p.chooseVoicing(v, at: index) } label: {
                                            VStack(spacing: 4) {
                                                ChordDiagram(voicing: v, courses: app.instrument.courses.count)
                                                    .frame(width: 64, height: 72)
                                                Text((v.usesOpenStrings && v.lowestFret <= 4 ? "откр." : "лад \(v.lowestFret)") + " · \(v.notes.count) стр.")
                                                    .font(Typo.inter(10)).foregroundStyle(Theme.textTertiary)
                                            }
                                            .padding(8)
                                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(selected ? AnyShapeStyle(Theme.textPrimary.opacity(0.12)) : AnyShapeStyle(Theme.cardFill)))
                                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? Theme.textPrimary.opacity(0.7) : Theme.hairline, lineWidth: 1))
                                        }
                                        .buttonStyle(PressableStyle())
                                    }
                                }
                            }
                            .scrollIndicators(.hidden)
                        }
                    }
                    Card {
                        CardRow(title: "Порядок", subtitle: "или удерживайте аккорд в ленте и тяните") {
                            HStack(spacing: 6) {
                                RoundIconButton(icon: .chevronLeft, size: 36, iconSize: 14, label: "Раньше") {
                                    p.moveChord(from: index, to: index - 1)
                                    app.sheet = .progressionChord(index - 1)
                                }
                                .disabled(index == 0).opacity(index == 0 ? 0.35 : 1)
                                RoundIconButton(icon: .chevronRight, size: 36, iconSize: 14, label: "Позже") {
                                    p.moveChord(from: index, to: index + 1)
                                    app.sheet = .progressionChord(index + 1)
                                }
                                .disabled(index + 1 >= p.progression.chords.count).opacity(index + 1 >= p.progression.chords.count ? 0.35 : 1)
                            }
                        }
                        CardRow(title: "Вставить аккорд") {
                            HStack(spacing: 6) {
                                Button { app.sheet = .progressionInsert(index) } label: { Chip(text: "перед") }.buttonStyle(PressableStyle())
                                Button { app.sheet = .progressionInsert(index + 1) } label: { Chip(text: "после") }.buttonStyle(PressableStyle())
                            }
                        }
                        CardRow(title: "Тактов", subtitle: "сколько звучит этот аккорд") {
                            ValueStepper(value: "\(chord.bars)", canDecrement: chord.bars > 1, canIncrement: chord.bars < 8,
                                         decrement: { p.setBars(at: index, chord.bars - 1) }, increment: { p.setBars(at: index, chord.bars + 1) })
                        }
                        Button {
                            p.removeChord(at: index)
                            app.sheet = nil
                        } label: {
                            CardRow(title: "Убрать из прогрессии", showsDivider: false) { Icon(.trash, size: 18, color: Theme.danger) }
                                .foregroundStyle(Theme.danger)
                        }
                        .buttonStyle(.plain)
                        .disabled(p.progression.chords.count <= 1)
                        .opacity(p.progression.chords.count <= 1 ? 0.4 : 1)
                    }
                }
                Text(index == nil || insertAt != nil ? "Какой аккорд" : "Заменить на").font(Typo.caption).foregroundStyle(Theme.textTertiary)
                Segments(options: [(false, "Из тональности"), (true, "Любой аккорд")], selection: $anyChord)
                if anyChord { anyChordPicker(key: p.key) } else {
                ForEach(ProgressionController.palette, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.title).font(Typo.inter(12, .medium)).foregroundStyle(Theme.textSecondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                            ForEach(group.numerals, id: \.self) { numeral in
                                if let pc = ProgressionChord(numeral: numeral) {
                                    let name = compactChordName(pc.chord.name(root: pc.root(in: p.key), formatter: app.chordFormatter))
                                    let selected = chord.map { $0.degree == pc.degree && $0.accidental == pc.accidental && $0.chordId == pc.chordId } ?? false
                                    Button {
                                        apply(pc)
                                    } label: {
                                        VStack(spacing: 1) {
                                            Typo.notes(name, size: 15, weight: .semibold).foregroundStyle(Theme.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                                            Typo.notes(pc.numeral, size: 10).foregroundStyle(Theme.textTertiary)
                                        }
                                        .frame(maxWidth: .infinity, minHeight: 48)
                                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? AnyShapeStyle(Theme.textPrimary.opacity(0.12)) : AnyShapeStyle(Theme.cardFill)))
                                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? Theme.textPrimary.opacity(0.7) : Theme.hairline, lineWidth: 1))
                                    }
                                    .buttonStyle(PressableStyle())
                                }
                            }
                        }
                    }
                }
                }
            }
        }
    }

    /// Any root × any type of the library (TH-3b), named at once on the button.
    @ViewBuilder private func anyChordPicker(key: NoteName) -> some View {
        let root = NoteName.simpleSpelling(ofPitchClass: anyRoot, preferFlats: [1, 3, 8, 10].contains(anyRoot))
        let type = ChordLibrary.anyChord(id: anyType) ?? ChordLibrary.major7
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                ForEach(0..<12, id: \.self) { pc in
                    let name = NoteName.simpleSpelling(ofPitchClass: pc, preferFlats: [1, 3, 8, 10].contains(pc))
                    Button { anyRoot = pc } label: {
                        Typo.notes(app.chordFormatter.string(name), size: 15, weight: .medium).foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(anyRoot == pc ? Theme.textPrimary.opacity(0.12) : Color.white.opacity(0.04)))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(anyRoot == pc ? Theme.textPrimary.opacity(0.7) : Theme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            FlowLayout(spacing: 6) {
                ForEach(ChordLibrary.full, id: \.id) { c in
                    Button { anyType = c.id } label: { Chip(text: chordChipName(c), style: anyType == c.id ? .emphasized : .muted) }
                        .buttonStyle(PressableStyle())
                }
            }
            SheetButton(title: "Поставить " + compactChordName(type.name(root: root, formatter: app.chordFormatter))) {
                apply(ProgressionChord(root: root, in: key, chordId: type.id))
            }
        }
    }

    private func bar(_ index: Int) -> Int {
        let p = app.fretboard.progression
        return 1 + p.progression.chords.prefix(index).reduce(0) { $0 + (p.barsPerChord ?? $1.bars) }
    }
}

/// «Ритм» (FB-24): bars per chord, stroke pattern, loop; the tempo is the metronome's.
struct FretProgressionSheet: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let p = app.fretboard.progression
        DesignSheet(title: "Ритм", height: 610, close: { app.sheet = nil }) {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Тактов на аккорд").font(Typo.caption).foregroundStyle(Theme.textTertiary)
                    Segments(options: [(0, "Как в схеме"), (1, "1"), (2, "2"), (4, "4")],
                             selection: Binding(get: { p.barsPerChord ?? 0 }, set: { p.barsPerChord = $0 == 0 ? nil : $0 }))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Удар").font(Typo.caption).foregroundStyle(Theme.textTertiary)
                    Segments(options: [(StrumRhythm.perBar, "На такт"), (.perBeat, "На долю"), (.downUpEighths, "Вниз-вверх")],
                             selection: Binding(get: { p.rhythm }, set: { p.rhythm = $0 }))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Подписи на грифе").font(Typo.caption).foregroundStyle(Theme.textTertiary)
                    Segments(options: [(false, "Ноты"), (true, "Ступени")],
                             selection: Binding(get: { p.showsDegrees }, set: { p.showsDegrees = $0 }))
                }
                Card {
                    CardRow(title: "По кругу") { ToggleSwitch(isOn: Binding(get: { p.loop }, set: { p.loop = $0 }), label: "По кругу") }
                    CardRow(title: "Щелчок метронома", subtitle: "с отсчётом в такт") {
                        ToggleSwitch(isOn: Binding(get: { p.click }, set: { p.click = $0 }), label: "Щелчок метронома")
                    }
                    CardRow(title: "Темп", subtitle: "общий с метрономом", showsDivider: false) {
                        Text("\(Int(app.metronome.bpm)) BPM · \(app.metronome.meter.numerator)/\(app.metronome.meter.denominator)")
                    }
                }
            }
        }
    }
}

private struct RibbonCard: View {
    let bar: Int
    let name: String
    let caption: String
    let warning: Bool
    let missing: Bool
    let selected: Bool
    /// While it plays: the bar's beats as dots instead of the numeral — you see when the change comes.
    var beats: Int?
    var beat: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("такт \(bar)").font(Typo.inter(10)).foregroundStyle(Theme.textTertiary)
            Typo.notes(name, size: 17, weight: .medium)
                .foregroundStyle(missing ? Theme.textTertiary : Theme.textPrimary).lineLimit(1)
            if let beats {
                HStack(spacing: 3) {
                    ForEach(0..<min(beats, 9), id: \.self) { i in
                        Circle().fill(i == beat ? Theme.textPrimary : Color.white.opacity(0.2)).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 13)
                .accessibilityHidden(true)
            } else {
                Typo.notes(caption, size: 11).foregroundStyle(warning ? Theme.sharp : Theme.textSecondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(minWidth: 64, minHeight: 64, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(selected ? AnyShapeStyle(Theme.textPrimary.opacity(0.12)) : AnyShapeStyle(Theme.cardFill)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(selected ? Theme.textPrimary.opacity(0.7) : Theme.hairline, lineWidth: 1))
    }
}

// MARK: Progression sheets (canvas 2026-11-25)

/// Library templates as the sheets name them: the numerals and the style.
enum ProgressionTemplateInfo {
    static let order = ["jazz-251", "fifties", "andalusian", "pop", "sad-pop", "three", "jazz-1625", "minor-251", "blues",
                        "epic-minor", "aeolian", "phrygian", "power"]
    static let info: [String: (title: String, style: String)] = [
        "pop": ("I–V–vi–IV", "поп"), "fifties": ("I–vi–IV–V", "50-е"), "sad-pop": ("vi–IV–I–V", "поп"),
        "three": ("I–IV–V", "блюз, рок"), "jazz-251": ("ii–V–I", "джаз"), "jazz-1625": ("I–vi–ii–V", "джаз"),
        "minor-251": ("iiø–V–i", "джаз, минор"), "blues": ("I–IV–V · 12 тактов", "блюз"), "andalusian": ("i–♭VII–♭VI–V", "андалузская"),
        "epic-minor": ("i–♭VI–♭III–♭VII", "эпический минор"), "aeolian": ("i–♭VI–♭VII–i", "минор"), "phrygian": ("i–♭II", "фригийский"),
        "power": ("I5–♭VI5–♭VII5", "пауэр-аккорды"),
    ]
}

/// «Прогрессии» (canvas «Прогрессии», top 180): «Мои прогрессии» with the tempo and a check on the open one,
/// «Шаблоны · от выбранной ноты», «Новая прогрессия».
struct FretProgressionsSheet: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let p = app.fretboard.progression
        DesignSheet(title: "Прогрессии", height: 664, close: { app.sheet = nil }) {
            VStack(spacing: 12) {
                if !p.saved.isEmpty {
                    VStack(spacing: 0) {
                        SectionCaption(text: "Мои прогрессии")
                        Card {
                            ForEach(p.saved) { item in
                                Button {
                                    p.open(item)
                                    if let bpm = item.bpm { app.metronome.bpm = Double(bpm) }
                                    app.sheet = nil
                                } label: {
                                    ProgressionListRow(title: item.name, subtitle: item.note ?? chordsCount(item.chords.count),
                                                       tempo: item.bpm.map { "♩=\($0)" }, checked: p.activeSavedId == item.id)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                VStack(spacing: 0) {
                    SectionCaption(text: "Шаблоны · от выбранной ноты")
                    Card {
                        ForEach(ProgressionTemplateInfo.order, id: \.self) { id in
                            if let info = ProgressionTemplateInfo.info[id], p.templates.contains(where: { $0.id == id }) {
                                Button {
                                    p.templateId = id
                                    app.sheet = nil
                                } label: {
                                    ProgressionListRow(title: info.title, subtitle: info.style, tempo: nil,
                                                       checked: p.activeSavedId == nil && !p.isCustom && p.templateId == id)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        } footer: {
            SheetButton(title: "Новая прогрессия") {
                if let first = ProgressionChord(numeral: p.isMinor ? "i" : "I") { p.useChords([first], key: p.key) }
                app.sheet = .progressionChord(nil)
            }
        }
    }

    private func chordsCount(_ n: Int) -> String { "\(n) \(ruPlural(n, "аккорд", "аккорда", "аккордов"))" }
}

/// Row of «Прогрессии» (canvas: 60 pt, padding 0 16, gap 12; title 15 primary, subtitle 12; «♩=92» 15 secondary;
/// a 20 pt check or its place).
private struct ProgressionListRow: View {
    let title: String
    let subtitle: String
    let tempo: String?
    let checked: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Typo.notes(title, size: 15).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Typo.notes(subtitle, size: 12).foregroundStyle(Theme.textTertiary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let tempo { Text(tempo).font(Typo.inter(15)).foregroundStyle(Theme.textSecondary) }
            Group {
                if checked { Icon(.check, size: 20, lineWidth: 2, color: Theme.textPrimary) } else { Color.clear }
            }
            .frame(width: 20, height: 20)
        }
        .padding(.horizontal, 16)
        .frame(height: 61)   // canvas: 60 + the 1 pt border below (content-box)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
        .contentShape(Rectangle())
    }
}

/// «Прогрессия от A» (canvas «Нота → прогрессия», top 300): major or minor from the pressed note, common
/// progressions with their chords; «Показать на грифе» opens «Прогрессия» from that place.
struct ProgressionFromNoteSheet: View {
    @Environment(AppModel.self) private var app
    let spot: NeckSpot
    @State private var minor = false
    @State private var picked = 0

    static let major: [(numerals: String, caption: String)] = [
        ("I V vi IV", "I – V – vi – IV · поп"), ("I IV V", "I – IV – V · блюз, рок"),
        ("ii V I", "ii – V – I · джаз"), ("vi IV I V", "vi – IV – I – V"),
    ]
    static let minorList: [(numerals: String, caption: String)] = [
        ("i ♭VI ♭III ♭VII", "i – VI – III – VII · рок-баллада"), ("i iv v", "i – iv – v · минор"),
        ("i ♭VII ♭VI V", "i – VII – VI – V · андалузская"), ("ii° V i", "ii° – V – i · джаз"),
    ]

    private var root: NoteName? {
        guard let p = app.fretboard.fretboard?.pitch(course: spot.course, fret: spot.fret) else { return nil }
        return ScaleSpeller.preferredTonic(pitchClass: p.pitchClass, scale: minor ? ScaleLibrary.naturalMinor : ScaleLibrary.major)
    }

    var body: some View {
        let rootName = root.map { app.formatter.string($0) } ?? ""
        let list = minor ? Self.minorList : Self.major
        DesignSheet(title: "Прогрессия от \(rootName)", height: 544, close: { app.sheet = nil }) {
            VStack(spacing: 12) {
                Segments(options: [(false, "\(rootName) мажор"), (true, "\(rootName) минор")],
                         selection: Binding(get: { minor }, set: { minor = $0; picked = 0 }))
                VStack(spacing: 0) {
                    SectionCaption(text: "Прогрессии от \(rootName)")
                    Card {
                        ForEach(Array(list.enumerated()), id: \.offset) { index, item in
                            Button { picked = index } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Typo.notes(chordNames(item.numerals), size: 15, weight: picked == index ? .semibold : .regular)
                                            .foregroundStyle(Theme.textPrimary).lineLimit(1)
                                        Typo.notes(item.caption, size: 12).foregroundStyle(Theme.textTertiary).lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    if picked == index { Icon(.check, size: 18, lineWidth: 2, color: Theme.textPrimary) }
                                }
                                .padding(.leading, 16).padding(.trailing, 14)
                                .frame(minHeight: 59)
                                .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(picked == index ? .isSelected : [])
                        }
                    }
                }
            }
        } footer: {
            SheetButton(title: "Показать на грифе") {
                guard let root else { return }
                let chords = list[picked].numerals.split(separator: " ").compactMap { ProgressionChord(numeral: String($0)) }
                let fretboard = app.fretboard
                fretboard.progression.useChords(chords, key: root)
                fretboard.mode = .progression
                fretboard.progression.start(from: spot)
                app.sheet = nil
            }
        }
    }

    /// «A · E · F♯m · D»: the chords of the numerals in this key.
    private func chordNames(_ numerals: String) -> String {
        guard let root else { return "" }
        return numerals.split(separator: " ").compactMap { ProgressionChord(numeral: String($0)) }
            .map { compactChordName($0.chord.name(root: $0.root(in: root), formatter: app.chordFormatter)) }
            .joined(separator: " · ")
    }
}
