import SwiftUI
import TruverTheory

// FB-26 «Гамма · Аккорд · Поиск», FB-9 chord library, FB-10 search, FB-21 chords from a note, FB-25 scale from a note,
// the note menu (canvas «v1.x · P1»).

/// Mode switcher under the header (canvas: 34 pt segments in a 20 pt-radius tray).
struct FretModeSwitcher: View {
    @Binding var mode: FretMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach([(FretMode.scale, "Гамма"), (.chord, "Аккорд"), (.search, "Поиск"), (.progression, "Прогрессия")], id: \.0) { value, title in
                let selected = value == mode
                Button { withAnimation(Motion.out(Motion.Duration.quick)) { mode = value } } label: {
                    Text(title).font(selected ? Typo.segmentSelected : Typo.segment)
                        .lineLimit(1).minimumScaleFactor(0.85)
                        .foregroundStyle(selected ? Theme.background : Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(Capsule().fill(selected ? Theme.accent : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

/// Chord row: root «A ▾», type chips (m, m7, 7, maj7 …), library button.
struct ChordPickerRow: View {
    @Environment(AppModel.self) private var app
    let openLibrary: () -> Void

    static let quickTypes = ["maj", "m", "7", "m7", "maj7", "sus4", "m7b5", "dim", "add9", "9"]

    var body: some View {
        let fretboard = app.fretboard
        HStack(spacing: 8) {
            Menu {
                ForEach(0..<12, id: \.self) { pc in
                    let name = NoteName.simpleSpelling(ofPitchClass: pc, preferFlats: [1, 3, 8, 10].contains(pc) && pc != 1)
                    Button(app.formatter.string(name)) { fretboard.chordAnchor = nil; fretboard.chordRoot = name }
                }
            } label: {
                HStack(spacing: 4) {
                    Typo.notes(app.formatter.string(fretboard.chordRoot), size: 15, weight: .semibold).foregroundStyle(Theme.textPrimary)
                    Icon(.chevronDown, size: 12, color: Theme.textTertiary)
                }
                .padding(.horizontal, 12).frame(height: 36)
                .background(Capsule().fill(Theme.cardFill))
                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            }
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(Self.quickTypes + app.settings.customChords.map(\.id), id: \.self) { id in
                        if let chord = ChordLibrary.anyChord(id: id) {
                            Button { fretboard.chordId = id } label: {
                                Typo.notes(chordChipName(chord), size: 12, weight: .medium)
                                    .foregroundStyle(fretboard.chordId == id ? Theme.textPrimary : Theme.textSecondary)
                                    .padding(.horizontal, 12).frame(height: 30)
                                    .background(Capsule().fill(fretboard.chordId == id ? Theme.textPrimary.opacity(0.12) : Theme.fill))
                                    .overlay(Capsule().strokeBorder(fretboard.chordId == id ? Theme.textPrimary.opacity(0.6) : Theme.hairlineStrong, lineWidth: 1))
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            RoundIconButton(icon: .rename, size: 44, label: "Все аккорды", action: openLibrary)
        }
    }
}

/// Inversions «Am7 · Am7/C · Am7/G» and «Гаммы ›».
struct ChordInversionRow: View {
    @Environment(AppModel.self) private var app
    /// The main chord screen also switches the neck labels (canvas: «Ноты / Ступени / Пальцы»).
    var showsLabels = false
    let showScales: () -> Void

    private var labelTitle: String {
        switch app.fretboard.chordLabels {
        case .degrees: return "Ступени"
        case .fingers: return "Пальцы"
        default: return "Ноты"
        }
    }

    var body: some View {
        let fretboard = app.fretboard
        let tones = fretboard.chord.spell(root: fretboard.chordRoot)
        HStack(spacing: 6) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(Array(tones.prefix(4).enumerated()), id: \.offset) { index, tone in
                        let bass: Int? = index == 0 ? nil : tone.pitchClass
                        let selected = fretboard.chordBass == bass
                        Button { fretboard.chordBass = bass } label: {
                            Typo.notes(fretboard.chordName(bass: bass), size: 12, weight: .medium)
                                .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                                .padding(.horizontal, 12).frame(height: 30)
                                .background(Capsule().fill(selected ? Theme.textPrimary.opacity(0.12) : Theme.fill))
                                .overlay(Capsule().strokeBorder(selected ? Theme.textPrimary.opacity(0.6) : Theme.hairlineStrong, lineWidth: 1))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
            .scrollIndicators(.hidden)
            if showsLabels {
                Button {
                    switch fretboard.chordLabels {
                    case .notes: fretboard.chordLabels = .degrees
                    case .degrees: fretboard.chordLabels = .fingers
                    default: fretboard.chordLabels = .notes
                    }
                } label: { Chip(text: labelTitle) }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Подписи: \(labelTitle)")
            }
            Button(action: showScales) {
                Text("Гаммы ›").font(Typo.chip).foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .frame(height: 30)
    }
}

/// «‹ 1 из 14 · от 5-го лада › ▶ Сыграть».
struct ChordNavigationRow: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let fretboard = app.fretboard
        HStack(spacing: 8) {
            RoundIconButton(icon: .chevronLeft, size: 44, label: "Предыдущее расположение") { fretboard.stepVoicing(-1) }
            VStack(spacing: 0) {
                if fretboard.voicings.isEmpty {
                    Text("Расположений нет").font(Typo.inter(12)).foregroundStyle(Theme.textTertiary)
                } else {
                    (Text("\(fretboard.voicingIndex + 1)").foregroundColor(Theme.textPrimary).font(Typo.inter(12, .semibold))
                        + Text(" из \(fretboard.voicings.count)"))
                    Text(fretboard.currentVoicing.map { fretboard.voicingTitle($0) } ?? "")
                }
            }
            .font(Typo.inter(12)).foregroundStyle(Theme.textTertiary)
            .lineLimit(1).minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
            RoundIconButton(icon: .chevronRight, size: 44, label: "Следующее расположение") { fretboard.stepVoicing(1) }
            RoundIconButton(icon: .music, size: 44, label: "Арпеджио") { fretboard.playVoicing(arpeggio: true) }
                .disabled(fretboard.voicings.isEmpty)
            Button { fretboard.playVoicing() } label: {
                HStack(spacing: 8) {
                    Icon(.play, size: 18, color: Theme.background)
                    Text("Сыграть").font(Typo.inter(16, .semibold)).foregroundStyle(Theme.background)
                }
                .padding(.leading, 14).padding(.trailing, 18).frame(height: 52)
                .background(Capsule().fill(Theme.textPrimary))
                .shadow(color: .black.opacity(0.35), radius: 9, y: 6)
                .fixedSize()
            }
            .buttonStyle(PressableStyle())
            .layoutPriority(1)
            .disabled(fretboard.voicings.isEmpty)
        }
    }
}

/// «Поиск»: prompt + «Сбросить».
struct SearchPromptRow: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack {
            Text("Отметьте ноты на грифе").font(Typo.inter(14)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Button { app.fretboard.marked = [] } label: { Chip(text: "Сбросить", icon: .refresh, style: .muted) }
                .buttonStyle(PressableStyle())
                .disabled(app.fretboard.marked.isEmpty)
        }
        .frame(height: 44)
    }
}

/// Result card (canvas: «Am7 · или C6/A · 4 ноты: A C E G»), or «Отметьте хотя бы 3 ноты», or «Ничего не найдено».
struct SearchResultCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let fretboard = app.fretboard
        let pitches = fretboard.markedPitches
        let names = pitches.map { app.chromaticName($0).filter { !$0.isNumber } }
        VStack(alignment: .leading, spacing: 10) {
            if pitches.count < 3 {
                VStack(spacing: 4) {
                    Text("Отметьте хотя бы 3 ноты").font(Typo.inter(15, .medium)).foregroundStyle(Theme.textPrimary)
                    Text("Тап по ладу — отметить, повторный — снять").font(Typo.caption).foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity).padding(14)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.cardFill))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
            } else if let best = fretboard.searchChords.first {
                let alt = fretboard.searchChords.dropFirst().first
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Typo.notes(compactChordName(best.name(formatter: app.formatter)), size: 22, weight: .semibold).foregroundStyle(Theme.textPrimary)
                    Typo.notes((alt.map { "или " + compactChordName($0.name(formatter: app.formatter)) + " · " } ?? "") + "\(pitches.count) \(ruPlural(pitches.count, "нота", "ноты", "нот")): " + names.joined(separator: " "), size: 13)
                        .foregroundStyle(Theme.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.cardFill))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                HStack(spacing: 8) {
                    Button { fretboard.openInChordMode(best) } label: { Chip(text: "Открыть в «Аккорде»") }.buttonStyle(PressableStyle())
                    Button { app.sheet = .searchResults } label: { Chip(text: "Гаммы с этими нотами ›") }.buttonStyle(PressableStyle())
                }
            } else {
                VStack(spacing: 4) {
                    Text("Ничего не найдено").font(Typo.inter(15, .medium)).foregroundStyle(Theme.textPrimary)
                    // Canvas «Ничего не найдено»: the closest chord and a way to it.
                    let nearest = ChordRecognizer.nearest(pitchClasses: Set(pitches.map(\.pitchClass)), bass: pitches.first?.pitchClass)
                    Typo.notes(nearest.map { "Такого аккорда нет в библиотеке. Ближайшее: \(compactChordName($0.match.name(formatter: app.formatter))) — \($0.matched) \(ruPlural($0.matched, "нота", "ноты", "нот")) из \(Set(pitches.map(\.pitchClass)).count)" }
                               ?? "Такого аккорда нет в библиотеке · " + names.joined(separator: " "), size: 12)
                        .foregroundStyle(Theme.textTertiary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(14)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.cardFill))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                HStack(spacing: 8) {
                    if let nearest = ChordRecognizer.nearest(pitchClasses: Set(pitches.map(\.pitchClass)), bass: pitches.first?.pitchClass) {
                        Button { fretboard.openInChordMode(nearest.match) } label: { Chip(text: "Показать ближайшее") }.buttonStyle(PressableStyle())
                    }
                    Button { app.sheet = .searchResults } label: { Chip(text: "Гаммы с этими нотами ›") }.buttonStyle(PressableStyle())
                }
            }
        }
    }
}

/// Note menu (long press): «A2 · 6-я струна, 5-й лад · ступень 4» and five actions (canvas «меню ноты»).
struct NoteMenu: View {
    @Environment(AppModel.self) private var app
    let spot: NeckSpot
    let close: () -> Void

    var body: some View {
        let fretboard = app.fretboard
        let pitch = fretboard.fretboard?.pitch(course: spot.course, fret: spot.fret)
        let string = app.instrument.courses.count - spot.course
        let degree = pitch.flatMap { fretboard.scale.degreeIndex(of: $0, tonic: fretboard.settings.tonic) }.map { fretboard.scale.degrees[$0].label.description }
        VStack(alignment: .leading, spacing: 0) {
            Typo.notes("\(pitch.map { app.chromaticName($0) } ?? "") · \(string)-я струна, \(spot.fret)-й лад" + (degree.map { " · ступень \($0)" } ?? ""), size: 12)
                .foregroundStyle(Theme.textTertiary).padding(.horizontal, 14).padding(.vertical, 8)
            item(.fretboard, "Гамма от этой ноты") { app.sheet = .scaleFromNote(spot.course, spot.fret) }
            item(.chevronRight, "Путь отсюда") { app.fretboard.startPath(from: spot) }
            item(.music, "Аккорды от этой ноты") { app.sheet = .chordsFromNote(spot.course, spot.fret) }
            item(.list, "Прогрессия отсюда") { app.fretboard.progression.start(from: spot) }
            if fretboard.mode == .scale {
                let hidden = fretboard.isHidden(spot)
                item(.close, hidden ? "Показать ноту" : (degree == nil ? "Добавить ноту" : "Скрыть ноту"), danger: degree != nil && !hidden) {
                    fretboard.toggle(course: spot.course, fret: spot.fret)
                }
            }
        }
        .frame(width: 232)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x282a2f, opacity: 0.98)))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.7), radius: 25, y: 20)
    }

    private func item(_ icon: AppIcon, _ title: String, danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            close()
            action()
        } label: {
            HStack(spacing: 10) {
                Icon(icon, size: 16, color: danger ? Theme.danger : Theme.textBody)
                Text(title).font(Typo.inter(15)).foregroundStyle(danger ? Theme.danger : Theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).frame(height: 41)
            .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A small chord box (canvas list rows): strings vertical, 5 frets, dots, × and ○ above, the first fret number.
struct ChordDiagram: View {
    let voicing: ChordVoicing
    let courses: Int

    var body: some View {
        Canvas { context, size in
            let top: CGFloat = 8, left: CGFloat = 8
            let w = size.width - left - 2, h = size.height - top - 2
            let fretted = voicing.notes.map(\.fret).filter { $0 > 0 }
            let first = voicing.usesOpenStrings && (fretted.max() ?? 0) <= 5 ? 1 : max(1, fretted.min() ?? 1)
            let dx = courses > 1 ? w / CGFloat(courses - 1) : 0, dy = h / 5
            let line = GraphicsContext.Shading.color(Color.white.opacity(0.35))
            for c in 0..<courses {
                var p = Path(); p.move(to: CGPoint(x: left + CGFloat(c) * dx, y: top)); p.addLine(to: CGPoint(x: left + CGFloat(c) * dx, y: top + h))
                context.stroke(p, with: line, lineWidth: 0.8)
            }
            for r in 0...5 {
                var p = Path(); p.move(to: CGPoint(x: left, y: top + CGFloat(r) * dy)); p.addLine(to: CGPoint(x: left + w, y: top + CGFloat(r) * dy))
                context.stroke(p, with: line, lineWidth: r == 0 && first == 1 ? 2 : 0.8)
            }
            if first > 1 {
                context.draw(Text("\(first)").font(Typo.fixed(7)).foregroundColor(Theme.textTertiary), at: CGPoint(x: 2, y: top + dy / 2))
            }
            for (c, fret) in voicing.frets.enumerated() {
                let x = left + CGFloat(c) * dx
                guard let fret else {
                    context.draw(Text("×").font(Typo.fixed(7)).foregroundColor(Theme.textTertiary), at: CGPoint(x: x, y: 3))
                    continue
                }
                if fret == 0 {
                    context.stroke(Path(ellipseIn: CGRect(x: x - 2, y: 1, width: 4, height: 4)), with: .color(Theme.textSecondary), lineWidth: 0.8)
                } else {
                    let row = CGFloat(fret - first) + 0.5
                    let r: CGFloat = min(3.2, dx * 0.42)
                    context.fill(Path(ellipseIn: CGRect(x: x - r, y: top + row * dy - r, width: 2 * r, height: 2 * r)), with: .color(Theme.textPrimary))
                }
            }
        }
        .frame(width: 58, height: 62)
        .accessibilityHidden(true)
    }
}

/// Chord box of the canvas lists (98 × 96, viewBox −6 0 98 96): strings 8…84, five frets 14.8 apart from y 14 to 88
/// (the nut 3 pt white 80 % from the first fret, else a 1 pt line), «×» 8 pt above muted strings, an open ring
/// r 2.6, dots r 4.4 #f3efe6, the first fret number at the left (8 pt).
struct ChordBox: View {
    let voicing: ChordVoicing
    let courses: Int

    /// First fret of the box: 1 for an open shape within 5 frets, else the lowest fretted note.
    static func firstFret(_ v: ChordVoicing) -> Int {
        let fretted = v.notes.map(\.fret).filter { $0 > 0 }
        return v.usesOpenStrings && (fretted.max() ?? 0) <= 5 ? 1 : max(1, fretted.min() ?? 1)
    }

    var body: some View {
        Canvas { context, _ in
            let ox: CGFloat = 6   // viewBox starts at x −6
            let first = Self.firstFret(voicing)
            let left: CGFloat = 8, right: CGFloat = 84, top: CGFloat = 14, step: CGFloat = 14.8
            let dx = courses > 1 ? (right - left) / CGFloat(courses - 1) : 0
            func x(_ c: Int) -> CGFloat { ox + left + CGFloat(c) * dx }
            for c in 0..<courses {
                var p = Path(); p.move(to: CGPoint(x: x(c), y: top)); p.addLine(to: CGPoint(x: x(c), y: top + 5 * step))
                context.stroke(p, with: .color(.white.opacity(0.35)), lineWidth: 1)
            }
            for r in 0...5 {
                let y = top + CGFloat(r) * step
                var p = Path(); p.move(to: CGPoint(x: ox + left, y: y)); p.addLine(to: CGPoint(x: ox + right, y: y))
                let nut = r == 0 && first == 1
                context.stroke(p, with: .color(.white.opacity(nut ? 0.8 : 0.25)), lineWidth: nut ? 3 : 1)
            }
            if first > 1 {
                // SVG text: baseline 24.4, start anchor at x 0.
                context.draw(Text("\(first)").font(Typo.fixed(8)).foregroundColor(Theme.textTertiary),
                             at: CGPoint(x: ox, y: 24.4), anchor: UnitPoint(x: 0, y: 0.78))
            }
            for (c, fret) in voicing.frets.enumerated() where c < courses {
                guard let fret else {
                    context.draw(Text("×").font(Typo.fixed(8)).foregroundColor(Theme.textTertiary), at: CGPoint(x: x(c), y: 9), anchor: UnitPoint(x: 0.5, y: 0.78))
                    continue
                }
                if fret == 0 {
                    context.stroke(Path(ellipseIn: CGRect(x: x(c) - 2.6, y: 6 - 2.6, width: 5.2, height: 5.2)), with: .color(Theme.textSecondary), lineWidth: 1)
                } else {
                    let y = top + (CGFloat(fret - first) + 0.5) * step
                    context.fill(Path(ellipseIn: CGRect(x: x(c) - 4.4, y: y - 4.4, width: 8.8, height: 8.8)), with: .color(Color(hex: 0xf3efe6)))
                }
            }
        }
        .frame(width: 98, height: 96)
        .accessibilityHidden(true)
    }
}

/// Voicing row of the canvas lists («Аккорд · Am7», «Аккорды от A»): box 98 × 96, title 15 medium, subtitle 12,
/// «проще всего» on the easiest, › on the rest; padding 8 14 8 8, gap 12.
struct VoicingCardRow: View {
    @Environment(AppModel.self) private var app
    let voicing: ChordVoicing
    let anchored: Bool
    let easiest: Bool
    var selected = false
    let action: () -> Void

    var body: some View {
        let card = app.fretboard.voicingCard(voicing, anchored: anchored)
        Button(action: action) {
            HStack(spacing: 12) {
                ChordBox(voicing: voicing, courses: app.instrument.courses.count)
                VStack(alignment: .leading, spacing: 3) {
                    Typo.notes(card.title, size: 15, weight: .medium).foregroundStyle(Theme.textPrimary)
                    Typo.notes(card.subtitle, size: 12).foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if easiest { Chip(text: "проще всего", style: .positive) } else { Icon(.chevronRight, size: 16, color: Theme.textTertiary) }
            }
            .padding(.leading, 8).padding(.trailing, 14).padding(.vertical, 8).padding(.bottom, 1)
            .background(selected ? Color.white.opacity(0.05) : .clear)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension FretboardController {
    /// Title and subtitle of a voicing in the canvas lists: «Открытый» / «A E G C E · 2 пальца», «Баррэ на 5-м · 6 струн»
    /// / «тоника на 6-й», «Частичное баррэ · 4 струны» / «A G C E · один палец», «От 12-го лада» / «тоника на 5-й ·
    /// 3 пальца»; from a pressed note (`anchored`): «Без баррэ · 4 струны» / «A E A C · 3 пальца», «Баррэ · 6 струн» /
    /// «полный звук · баррэ на 5-м», «С басом A1 · 7 струн» / «растяжка 3–7 лад».
    func voicingCard(_ v: ChordVoicing, anchored: Bool) -> (title: String, subtitle: String) {
        guard let app else { return ("", "") }
        let n = app.instrument.courses.count
        let count = v.notes.count
        let strings = "\(count) \(ruPlural(count, "струна", "струны", "струн"))"
        let spelled = chord.spell(root: chordRoot)
        let names = v.notes.map { note in
            spelled.first { $0.pitchClass == note.pitch.pitchClass }.map { app.formatter.string($0) }
                ?? app.chromaticName(note.pitch).filter { !$0.isNumber }
        }.joined(separator: " ")
        let fingers = v.fingers == 1 ? "один палец" : "\(v.fingers) \(ruPlural(v.fingers, "палец", "пальца", "пальцев"))"
        let bassString = n - v.bass.course
        let rootBass = v.bass.pitch.pitchClass == chordRoot.pitchClass
        let fretted = v.notes.map(\.fret).filter { $0 > 0 }
        let stretch = "растяжка \(fretted.min() ?? 0)–\(fretted.max() ?? 0) лад"
        if v.usesOpenStrings && v.lowestFret <= 4 { return ("Открытый", "\(names) · \(fingers)") }
        if bassString > 6 {
            let bass = app.chromaticName(v.bass.pitch)
            return ("С басом \(bass) · \(strings)", v.isStretch ? stretch : "\(names) · \(fingers)")
        }
        if let barre = v.barreFret {
            if count <= 4 { return ("Частичное баррэ · \(strings)", "\(names) · \(fingers)") }
            return anchored ? ("Баррэ · \(strings)", "полный звук · баррэ на \(barre)-м")
                : ("Баррэ на \(barre)-м · \(strings)", rootBass ? "тоника на \(bassString)-й" : "\(names) · \(fingers)")
        }
        if anchored { return ("Без баррэ · \(strings)", v.isStretch ? stretch : "\(names) · \(fingers)") }
        return ("От \(v.lowestFret)-го лада", (rootBass ? "тоника на \(bassString)-й" : names) + " · \(fingers)")
    }
}

/// One voicing row: diagram, «Am7 · от 5-го лада», subtitle, «удобно / растяжка».
struct VoicingRow: View {
    @Environment(AppModel.self) private var app
    let voicing: ChordVoicing
    let title: String
    let selected: Bool
    var showsDivider = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ChordDiagram(voicing: voicing, courses: app.instrument.courses.count)
                VStack(alignment: .leading, spacing: 2) {
                    Typo.notes(title, size: 15).foregroundStyle(Theme.textPrimary)
                    Typo.notes(app.fretboard.voicingSubtitle(voicing), size: 12).foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Text(voicing.isStretch ? "растяжка" : "удобно").font(Typo.caption).foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 14).frame(minHeight: 82)
            .background(selected ? Color.white.opacity(0.05) : .clear)
            .overlay(alignment: .bottom) { if showsDivider { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// «Аккорды от A · 6-я, 5-й лад» (canvas: sheet over the neck): types, voicings from this place, «Сыграть ещё» /
/// «Арпеджио»; nothing fits → «Опустить 11 / 9».
struct ChordsFromNoteSheet: View {
    @Environment(AppModel.self) private var app
    let spot: NeckSpot
    @State private var picked: ChordVoicing?
    @State private var omitted: Set<String> = []

    private var root: NoteName? {
        guard let p = app.fretboard.fretboard?.pitch(course: spot.course, fret: spot.fret) else { return nil }
        return ScaleSpeller.preferredTonic(pitchClass: p.pitchClass, scale: ScaleLibrary.major)
    }

    var body: some View {
        let fretboard = app.fretboard
        let string = app.instrument.courses.count - spot.course
        let rootName = root.map { app.formatter.string($0) } ?? ""
        DesignSheet(title: "Аккорды от \(rootName) · \(string)-я, \(spot.fret)-й лад", height: 552, close: close) {
            VStack(alignment: .leading, spacing: 12) {
                FlowLayout(spacing: 6) {
                    ForEach(typeIds, id: \.self) { id in
                        if let c = ChordLibrary.anyChord(id: id), let root {
                            Button {
                                picked = nil
                                fretboard.chordId = id
                            } label: {
                                NoteChip(text: fretboard.chordName(root, c), selected: fretboard.chordId == id)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if fretboard.voicings.isEmpty {
                    VStack(spacing: 6) {
                        Icon(.fretboard, size: 22, color: Theme.textSecondary)
                            .frame(width: 52, height: 52).background(Circle().fill(Theme.fill))
                            .overlay(Circle().strokeBorder(Theme.hairlineStrong, lineWidth: 1))
                        Text("Расположений не найдено").font(Typo.inter(17, .medium)).foregroundStyle(Theme.textBody).multilineTextAlignment(.center)
                        Typo.notes("От этого места \(fretboard.chordName()) не помещается в 4 пальца и 5 ладов"
                                   + (fretboard.omissionHint.map { ". Попробуйте опустить \($0.number)-ю ступень" } ?? ""), size: 12)
                            .foregroundStyle(Theme.textTertiary).multilineTextAlignment(.center).frame(maxWidth: 220)
                    }
                    .frame(maxWidth: .infinity).padding(18)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.cardFill))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                } else {
                    VStack(spacing: 0) {
                        SectionCaption(text: "От этого места")
                        Card {
                            ForEach(Array(fretboard.voicings.prefix(6).enumerated()), id: \.element.id) { index, v in
                                VoicingCardRow(voicing: v, anchored: true, easiest: index == 0, selected: picked == v) {
                                    picked = v
                                    fretboard.chordPreview = v
                                    fretboard.voicingIndex = index
                                    fretboard.playVoicing(v)
                                }
                            }
                        }
                    }
                }
            }
        } footer: {
            if fretboard.voicings.isEmpty {
                if let hint = fretboard.omissionHint {
                    outline("Опустить ступень \(hint.number)") { fretboard.chordOmitted.insert(hint) }
                } else {
                    outline("Упростить") { fretboard.chordId = simpler(fretboard.chordId) }
                }
            } else if picked != nil {
                SheetButton(title: "Сыграть ещё", icon: .play) { fretboard.playVoicing(picked) }
                outline("Арпеджио", icon: .music) { fretboard.playVoicing(picked, arpeggio: true) }
            }
        }
        .onAppear { if let root { fretboard.beginChordsFromNote(spot, root: root) } }
        .onDisappear { fretboard.endChordsFromNote() }
        .onChange(of: picked) { _, v in fretboard.chordPreview = v }
    }

    /// The current type (the key's chord on this degree) first, then the common ones.
    private var typeIds: [String] {
        // Canvas «Аккорды от A»: Am, A, Am7, A7, Amaj7, Asus4, Asus2, A5 — the key's chord first.
        let common = ["maj", "m", "m7", "7", "maj7", "sus4", "sus2", "5"]
        let current = app.fretboard.chordId
        return [current] + common.filter { $0 != current }
    }

    private func simpler(_ id: String) -> String {
        ["13#11": "7#11", "13": "9", "m13": "m9", "11": "9", "m11": "m9", "9": "7", "m9": "m7", "maj9": "maj7", "maj13": "maj7"][id] ?? "maj"
    }

    private func close() {
        app.fretboard.chordAnchor = nil
        app.sheet = nil
    }

    private func outline(_ title: String, icon: AppIcon? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Icon(icon, size: 16, color: Theme.textBody) }
                Text(title).font(Typo.button).foregroundStyle(Theme.textBody)
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Capsule().fill(Theme.cardFill))
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }
}

/// «Гамма от A · 6-я, 5-й лад» (FB-25): scale type chips, «Все гаммы», layout, position «от этой ноты»,
/// «Построить гамму».
struct ScaleFromNoteSheet: View {
    @Environment(AppModel.self) private var app
    let spot: NeckSpot
    @State private var scaleId = "aeolian"

    private static let common: [(String, String)] = [("aeolian", "Натур. минор"), ("major", "Мажор"), ("dorian", "Дорийский"),
                                                     ("phrygian-dominant", "Фриг. доминант"), ("harmonic-minor", "Гарм. минор"),
                                                     ("minor-pentatonic", "Минорная пентатоника")]

    private var positionHint: String {
        guard let r = app.fretboard.fromNotePreview?.position.fretRange else { return "Тоника — самая низкая нота позиции" }
        return "Тоника — самая низкая нота позиции, лады \(r.lowerBound)–\(r.upperBound)"
    }

    private func setLayout(_ kind: LayoutKind) {
        var s = app.fretboard.settings
        s.layout = kind
        app.fretboard.settings = s
        app.fretboard.previewScale(from: spot, scaleId: scaleId)
    }

    private func currentMode(pitch: Pitch?) -> Scale? {
        guard let pitch else { return nil }
        let f = app.fretboard
        return ScaleLibrary.mode(of: f.scale, tonic: f.settings.tonic, startingOn: pitch.pitchClass)
    }

    private func choices(pitch: Pitch?) -> [(String, String)] {
        var list = Self.common
        if let mode = currentMode(pitch: pitch) {
            list = [(mode.id, mode.names.ru + " · из гаммы")] + list.filter { $0.0 != mode.id }
        }
        if !list.contains(where: { $0.0 == scaleId }), let picked = ScaleLibrary.scale(id: scaleId) {
            list.insert((picked.id, picked.names.ru), at: 0)
        }
        return list
    }

    var body: some View {
        let fretboard = app.fretboard
        let pitch = fretboard.fretboard?.pitch(course: spot.course, fret: spot.fret)
        let string = app.instrument.courses.count - spot.course
        let name = pitch.map { app.chromaticName($0).filter { !$0.isNumber } } ?? ""
        DesignSheet(title: "Гамма от \(name) · \(string)-я, \(spot.fret)-й лад", height: 460, close: { app.sheet = nil }) {
            VStack(alignment: .leading, spacing: 14) {
                FlowLayout(spacing: 6) {
                    ForEach(choices(pitch: pitch), id: \.0) { id, title in
                        if ScaleLibrary.scale(id: id) != nil {
                            Button { scaleId = id } label: { Chip(text: title, style: scaleId == id ? .emphasized : .muted) }
                                .buttonStyle(PressableStyle())
                        }
                    }
                }
                Card {
                    // Stays in this sheet: the place on the neck is not lost.
                    Menu {
                        ForEach(ScaleLibrary.allWithUser.filter { !$0.needsReview }, id: \.id) { scale in
                            Button(scale.names.ru) { scaleId = scale.id }
                        }
                    } label: {
                        CardRow(title: "Все гаммы") {
                            HStack(spacing: 8) {
                                Text(ScaleLibrary.scale(id: scaleId)?.names.ru ?? "").lineLimit(1)
                                Icon(.chevronRight, size: 16, color: Theme.textTertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    Menu {
                        Button("3 ноты на струну") { setLayout(.threeNotesPerString) }
                        Button("Ящики") { setLayout(.boxes) }
                    } label: {
                        CardRow(title: "Раскладка") {
                            HStack(spacing: 8) {
                                Text(fretboard.settings.layout == .boxes ? "Ящики" : "3 ноты на струну")
                                Icon(.chevronRight, size: 16, color: Theme.textTertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    CardRow(title: "Позиция", subtitle: positionHint, showsDivider: false) {
                        Text("от этой ноты")
                    }
                }
            }
        } footer: {
            SheetButton(title: "Построить гамму") {
                fretboard.buildScale(from: spot, scaleId: scaleId)
                app.sheet = nil
            }
        }
        .onAppear {
            fretboard.menuSpot = spot
            // The mode of the current scale from this note comes first and is preselected (found on the iPhone:
            // B in G major offered «Фриг. доминант», not B Phrygian with the same notes).
            if let id = currentMode(pitch: pitch)?.id { scaleId = id }
            fretboard.previewScale(from: spot, scaleId: scaleId)
        }
        .onChange(of: scaleId) { _, id in fretboard.previewScale(from: spot, scaleId: id) }
        .onDisappear { fretboard.endScalePreview() }
        .onDisappear { fretboard.menuSpot = nil }
    }
}

/// «Отмечено 4 ноты» (canvas «Поиск — результаты», top 402): the marked notes, chords with their tones (missing ones
/// struck through), «точно» on an exact match; the scales that hold all the notes below.
struct SearchResultsSheet: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let fretboard = app.fretboard
        let names = Self.markedNames(fretboard, app: app)
        DesignSheet(title: "Отмечено \(names.count) \(ruPlural(names.count, "нота", "ноты", "нот"))", height: 442, close: { app.sheet = nil }) {
            VStack(spacing: 14) {
                HStack(spacing: 6) {
                    ForEach(names, id: \.self) { NoteChip(text: $0, style: .marked) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 0) {
                    SectionCaption(text: "Аккорды")
                    Card {
                        let chords = Array(fretboard.searchChords.prefix(4))
                        ForEach(Array(chords.enumerated()), id: \.offset) { index, match in
                            Button { fretboard.openInChordMode(match); app.sheet = nil } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Typo.notes(title(match), size: 16).foregroundStyle(Theme.textPrimary).lineLimit(1)
                                        tones(match)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    if match.missing.isEmpty && index == 0 { Chip(text: "точно") } else { Icon(.chevronRight, size: 16, color: Theme.textTertiary) }
                                }
                                .padding(.leading, 16).padding(.trailing, 14)
                                .frame(minHeight: 63)
                                .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                let scales = Array(fretboard.searchScales.prefix(6))
                if !scales.isEmpty {
                    VStack(spacing: 0) {
                        SectionCaption(text: "Гаммы")
                        Card {
                            ForEach(Array(scales.enumerated()), id: \.offset) { index, match in
                                Button {
                                    var s = fretboard.settings
                                    s.scaleId = match.scale.id
                                    s.tonic = match.tonic
                                    fretboard.settings = s
                                    fretboard.mode = .scale
                                    app.sheet = nil
                                } label: {
                                    CardRow(title: app.formatter.string(match.tonic) + " " + match.scale.names.ru.lowercased(),
                                            subtitle: "все \(names.count) \(ruPlural(names.count, "нота", "ноты", "нот")) в гамме", minHeight: 63) {
                                        Icon(.chevronRight, size: 16, color: Theme.textTertiary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    /// The marked notes once each, upwards from the bass: «A C E G».
    static func markedNames(_ fretboard: FretboardController, app: AppModel) -> [String] {
        let pitches = fretboard.markedPitches
        guard let bass = pitches.min(by: { $0.midi < $1.midi }) else { return [] }
        var seen = Set<Int>()
        return pitches.sorted { (($0.pitchClass - bass.pitchClass + 12) % 12) < (($1.pitchClass - bass.pitchClass + 12) % 12) }
            .filter { seen.insert($0.pitchClass).inserted }
            .map { app.chromaticName($0).filter { !$0.isNumber } }
    }

    /// «Am7», «C6 / A в басу», «Am9 · без ноны».
    private func title(_ match: ChordMatch) -> String {
        var name = compactChordName(match.chord.name(root: match.root, formatter: app.chordFormatter))
        if let bass = match.bass, bass.pitchClass != match.root.pitchClass { name += " / \(app.formatter.string(bass)) в басу" }
        if let missing = match.missing.first {
            let semitones = ((missing.pitchClass - match.root.pitchClass) % 12 + 12) % 12
            let degree: String = switch semitones {
            case 3, 4: "терции"
            case 7, 6, 8: "квинты"
            case 10, 11: "септимы"
            case 1, 2: "ноны"
            case 5: "кварты"
            default: "сексты"
            }
            name += " · без \(degree)"
        }
        return name
    }

    /// The chord's tones, letter-spaced; missing ones struck through.
    private func tones(_ match: ChordMatch) -> some View {
        let missing = Set(match.missing.map(\.pitchClass))
        var text = Text("")
        for (i, note) in match.chord.spell(root: match.root).enumerated() {
            let gone = missing.contains(note.pitchClass)
            let piece = Typo.notes(app.formatter.string(note), size: 12).foregroundColor(gone ? Theme.textTertiary : Theme.textBody)
            text = text + (i > 0 ? Text(" ") : Text("")) + (gone ? piece.strikethrough(true, color: Theme.textTertiary) : piece)
        }
        return text.kerning(0.96).lineLimit(1)
    }
}

/// Chord library (canvas «Аккорд — расположения»): roots, types, voicings by comfort, inversions, suitable scales.
struct ChordLibraryView: View {
    @Environment(AppModel.self) private var app
    var atScales = false
    let close: () -> Void
    @State private var showAllTypes = false

    /// Canvas: maj m 7 m7 maj7 dim aug sus2 sus4, then «ещё…» for the rest of the library.
    private var libraryTypes: [Chord] {
        let all = ChordLibrary.full.filter { !$0.isUserDefined }
        if showAllTypes { return all }
        return ["maj", "m", "7", "m7", "maj7", "dim", "aug", "sus2", "sus4"].compactMap { id in all.first { $0.id == id } }
    }

    var body: some View {
        let fretboard = app.fretboard
        VStack(spacing: 0) {
            // Canvas «Аккорд — библиотека» (FixFretChordLibrary): back 40, «Аккорд · Am7» 17 medium, the instrument.
            HStack(spacing: 12) {
                RoundIconButton(icon: .chevronLeft, label: "Назад", action: close)
                VStack(alignment: .leading, spacing: 1) {
                    Typo.notes("Аккорд · " + fretboard.chordName(), size: 17, weight: .medium).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Typo.notes(app.title, size: 12).foregroundStyle(Theme.textTertiary)
                }
                Spacer()
            }
            .frame(height: 44).padding(.horizontal, 20).padding(.top, 3)
            ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                        ForEach(0..<12, id: \.self) { pc in
                            let name = NoteName.simpleSpelling(ofPitchClass: pc, preferFlats: [3, 8, 10].contains(pc))
                            let selected = fretboard.chordRoot.pitchClass == pc
                            Button { fretboard.chordAnchor = nil; fretboard.chordRoot = name } label: {
                                Typo.notes(app.formatter.string(name), size: 15, weight: .medium).foregroundStyle(Theme.textPrimary)
                                    .frame(maxWidth: .infinity, minHeight: 40)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(selected ? 0.1 : 0.04)))
                                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Theme.selectedBorder : Theme.hairline, lineWidth: 1))
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                    FlowLayout(spacing: 6) {
                        // TH-8: the user's own chords first (long press — edit), then the library.
                        ForEach(app.settings.customChords, id: \.id) { c in
                            Button { fretboard.chordId = c.id } label: {
                                NoteChip(text: chordChipName(c), selected: fretboard.chordId == c.id)
                            }
                            .buttonStyle(PressableStyle())
                            .contextMenu {
                                Button("Изменить") { app.sheet = .chordBuilder(c.id) }
                                Button("Удалить", role: .destructive) {
                                    app.settings.customChords.removeAll { $0.id == c.id }
                                    if fretboard.chordId == c.id { fretboard.chordId = "maj" }
                                }
                            }
                        }
                        ForEach(libraryTypes, id: \.id) { c in
                            Button { fretboard.chordId = c.id } label: {
                                NoteChip(text: chordChipName(c), selected: fretboard.chordId == c.id)
                            }
                            .buttonStyle(PressableStyle())
                        }
                        Button { showAllTypes.toggle() } label: { NoteChip(text: showAllTypes ? "меньше" : "ещё…") }
                            .buttonStyle(PressableStyle())
                        if showAllTypes {
                            Button { app.sheet = .chordBuilder(nil) } label: { NoteChip(text: "+ Свой") }
                                .buttonStyle(PressableStyle())
                                .accessibilityLabel("Свой аккорд")
                        }
                    }
                    .padding(.top, 12)
                    VStack(spacing: 0) {
                        SectionCaption(text: "Расположения · от простых к сложным")
                        if fretboard.voicings.isEmpty {
                            ChordNoneState(chordName: fretboard.chordName(), hint: fretboard.omissionHint) {
                                if let hint = fretboard.omissionHint { fretboard.chordOmitted.insert(hint) }
                            }
                            .padding(.top, 24)
                        } else {
                            Card {
                                ForEach(Array(fretboard.voicings.prefix(8).enumerated()), id: \.element.id) { index, v in
                                    VoicingCardRow(voicing: v, anchored: false, easiest: index == 0, selected: false) {
                                        fretboard.voicingIndex = index
                                        fretboard.mode = .chord
                                        fretboard.playVoicing(v)
                                        close()
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 22)
                    VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Обращения").font(Typo.caption).foregroundStyle(Theme.textTertiary).padding(.horizontal, 4)
                        ChordInversionRow(showScales: { withAnimation(Motion.out(Motion.Duration.base)) { reader.scrollTo("scales", anchor: .top) } })
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Подходящие гаммы").id("scales").font(Typo.caption).foregroundStyle(Theme.textTertiary).padding(.horizontal, 4)
                        FlowLayout(spacing: 6) {
                            let pcs = Set(fretboard.chord.spell(root: fretboard.chordRoot).map(\.pitchClass))
                            ForEach(Array(ScaleFinder.scales(containing: pcs, preferredTonic: fretboard.chordRoot.pitchClass, limit: 6).enumerated()), id: \.offset) { _, m in
                                Button {
                                    var s = fretboard.settings
                                    s.scaleId = m.scale.id; s.tonic = m.tonic
                                    fretboard.settings = s
                                    fretboard.mode = .scale
                                    close()
                                } label: { Chip(text: app.formatter.string(m.tonic) + " " + m.scale.names.ru.lowercased()) }
                                .buttonStyle(PressableStyle())
                            }
                        }
                    }
                }
                    .padding(.top, 14)
                }
                // Room for the tuning pill floating above the tab bar.
                .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 72)
            }
            .onAppear { if atScales { DispatchQueue.main.async { reader.scrollTo("scales", anchor: .top) } } }
            }
        }
        .background(ScreenBackground())
    }
}

/// «Путь по грифу» (canvas sheet over the neck): 3 per string, 4 diagonal, one string; sequence; leave the path.
struct FretPathSheet: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let fretboard = app.fretboard
        DesignSheet(title: "Путь по грифу", height: 600, close: { app.sheet = nil }) {
            VStack(spacing: 14) {
                VStack(spacing: 0) {
                    SectionCaption(text: "Путь")
                    Card {
                        RadioRow(title: "3 ноты на струну", subtitle: "Позиция за позицией", selected: fretboard.pathKind == .threePerString) { fretboard.pathKind = .threePerString }
                        RadioRow(title: "4 ноты наискосок", subtitle: "Через весь гриф за один проход", selected: fretboard.pathKind == .fourDiagonal) { fretboard.pathKind = .fourDiagonal }
                        RadioRow(title: "По одной струне", subtitle: "Вдоль грифа, удобно для слайдов", selected: fretboard.pathKind == .oneString, showsDivider: false) { fretboard.pathKind = .oneString }
                    }
                }
                PlaybackControls()
            }
        } footer: {
            Button {
                fretboard.stopPlayback()
                fretboard.pathKind = nil
                fretboard.pathStart = nil
                app.sheet = nil
            } label: {
                Text("Выйти из пути").font(Typo.button).foregroundStyle(Theme.textBody)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(Capsule().fill(Theme.cardFill))
                    .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
        }
    }
}

/// «Расположений не найдено» (canvas «Аккорд — не помещается»): 52 pt icon, 17 medium title (168 wide),
/// 12 pt explanation with the degree to drop (160 wide), «Опустить ступень N» 48 pt outline button 44 below.
struct ChordNoneState: View {
    let chordName: String
    let hint: DegreeLabel?
    let omit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Icon(.fretboard, size: 24, color: Theme.textSecondary)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Theme.fill))
                .overlay(Circle().strokeBorder(Theme.hairlineStrong, lineWidth: 1))
            Text("Расположений не найдено").font(Typo.inter(17, .medium)).foregroundStyle(Theme.textBody)
                .multilineTextAlignment(.center).frame(maxWidth: 168).padding(.top, 12)
            Typo.notes("\(chordName) не помещается в 4 пальца в этом строе."
                       + (hint.map { " Попробуйте опустить \($0.number)-ю ступень" } ?? " Выберите другой тип"), size: 12)
                .foregroundStyle(Theme.textTertiary).lineSpacing(4).multilineTextAlignment(.center)
                .frame(maxWidth: 160).padding(.top, 6)
            if let hint {
                Button(action: omit) {
                    Text("Опустить ступень \(hint.number)").font(Typo.inter(15, .medium)).foregroundStyle(Theme.textBody)
                        .padding(.horizontal, 18).frame(height: 48)
                        .background(Capsule().fill(Theme.cardFill))
                        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
                .padding(.top, 44)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Type chips: lone symbols («°», «+», «ø7») were too small to read (UX check: «°» looked like «*»).
func chordChipName(_ c: Chord) -> String {
    switch c.id {
    case "maj": return "maj"
    case "dim": return "dim"
    case "dim7": return "dim7"
    case "aug": return "aug"
    default: return compactChordName(c.symbol)
    }
}

/// Russian plural: 1 нота, 2 ноты, 5 нот.
func ruPlural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let a = abs(n) % 100, b = a % 10
    if (11...14).contains(a) { return many }
    if b == 1 { return one }
    return (2...4).contains(b) ? few : many
}
