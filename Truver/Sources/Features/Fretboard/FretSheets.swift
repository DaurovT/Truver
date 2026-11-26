import SwiftUI
import TruverTheory

// MARK: Sheets

/// «Гамма» (canvas «Гамма», top 60): the tonic as chips, «Частые» scales with a check, «Ещё» — categories that open
/// their list in the sheet; the user's own scales and «Сохранить изменённую как свою» stay reachable.
struct FretScaleSheet: View {
    @Environment(AppModel.self) private var app
    @State private var category: ScaleCategory?

    /// «Частые»: canvas titles and subtitles (the selected one shows its steps instead).
    private static let common: [(id: String, title: String, subtitle: String)] = [
        ("major", "Мажор (ионийский)", "ионийский"), ("aeolian", "Натуральный минор", "эолийский"),
        ("major-pentatonic", "Пентатоника мажорная", "5 нот"), ("minor-pentatonic", "Пентатоника минорная", "5 нот"),
        ("blues", "Блюзовая", "6 нот · с ♭5"),
    ]
    /// «Ещё»: categories with a hint of what is inside.
    private static let more: [(category: ScaleCategory, title: String, subtitle: String?)] = [
        (.majorModes, "Лады", "дорийский, фригийский, лидийский…"), (.harmonicMinorModes, "Гармонические и мелодические", nil),
        (.exotic, "Экзотические", "венгерский, хиджаз…"), (.pentatonicAndBlues, "Пентатоники и блюз", nil),
        (.symmetric, "Симметричные", "целотонная, уменьшённые"), (.bebop, "Бибоп", nil), (.maqam, "Макамы", nil),
        (.user, "Мои гаммы", nil),
    ]

    var body: some View {
        let fretboard = app.fretboard
        DesignSheet(title: "Гамма", height: 784, close: { app.sheet = nil }) {
            VStack(spacing: 12) {
                if let category {
                    categoryList(category)
                } else {
                    VStack(spacing: 0) {
                        SectionCaption(text: "Тоника")
                        Card {
                            FlowLayout(spacing: 6) {
                                ForEach(0..<12, id: \.self) { pc in
                                    let selected = fretboard.settings.tonic.pitchClass == pc
                                    let name = selected ? fretboard.settings.tonic : NoteName.simpleSpelling(ofPitchClass: pc, preferFlats: false)
                                    Button { fretboard.setTonic(pitchClass: pc) } label: {
                                        NoteChip(text: app.formatter.string(name), selected: selected)
                                    }
                                    .buttonStyle(PressableStyle())
                                    .accessibilityAddTraits(selected ? .isSelected : [])
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if fretboard.isEdited {
                        // TH-8 / 6.1 п. 13: the edited scale becomes the user's own.
                        Card {
                            Button { app.sheet = .scaleBuilder(nil) } label: {
                                ScaleRow(title: "Сохранить изменённую как свою", subtitle: "точки и крестики на грифе", checked: false)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    VStack(spacing: 0) {
                        SectionCaption(text: "Частые")
                        Card {
                            ForEach(Self.common, id: \.id) { item in
                                let selected = fretboard.settings.scaleId == item.id
                                let scale = ScaleLibrary.scale(id: item.id)
                                Button { pick(item.id) } label: {
                                    ScaleRow(title: item.title, subtitle: selected ? (scale.map(Self.steps) ?? item.subtitle) : item.subtitle, checked: selected)
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(selected ? .isSelected : [])
                            }
                        }
                    }
                    VStack(spacing: 0) {
                        SectionCaption(text: "Ещё")
                        Card {
                            ForEach(Self.more, id: \.category) { item in
                                Button { withAnimation(Motion.out(Motion.Duration.quick)) { category = item.category } } label: {
                                    ScaleRow(title: item.title, subtitle: item.category == .user ? userSubtitle : item.subtitle, checked: false)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private var userSubtitle: String {
        let n = app.settings.customScales.count
        return n == 0 ? "своя гамма по ступеням" : "\(n) \(ruPlural(n, "гамма", "гаммы", "гамм"))"
    }

    /// One category: «‹ Все гаммы», then its scales (the user's own can be edited, and a new one made).
    @ViewBuilder private func categoryList(_ category: ScaleCategory) -> some View {
        let fretboard = app.fretboard
        let title = Self.more.first { $0.category == category }?.title ?? ""
        let list = ScaleLibrary.allWithUser.filter {
            category == .harmonicMinorModes ? ($0.category == .harmonicMinorModes || $0.category == .melodicMinorModes) : $0.category == category
        }
        VStack(spacing: 0) {
            Button { withAnimation(Motion.out(Motion.Duration.quick)) { self.category = nil } } label: {
                HStack(spacing: 6) {
                    Icon(.chevronLeft, size: 16, color: Theme.textTertiary)
                    Text("Все гаммы").font(Typo.caption).foregroundStyle(Theme.textTertiary)
                    Spacer()
                    Text(title).font(Typo.caption).foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 4).padding(.bottom, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Card {
                ForEach(list, id: \.id) { scale in
                    let selected = scale.id == fretboard.settings.scaleId
                    Button { pick(scale.id) } label: {
                        ScaleRow(title: scale.names.ru, subtitle: Self.steps(scale), checked: selected, showsChevron: false) {
                            if category == .user {
                                Button { app.sheet = .scaleBuilder(scale.id) } label: { Icon(.rename, size: 18, color: Theme.textSecondary).frame(width: 36, height: 36) }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Изменить «\(scale.names.ru)»")
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                if category == .user {
                    Button { app.sheet = .scaleBuilder(nil) } label: {
                        ScaleRow(title: "Новая гамма…", subtitle: "ступени от \(app.formatter.string(fretboard.settings.tonic))", checked: false, showsChevron: false) {
                            Icon(.plus, size: 18, color: Theme.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func pick(_ id: String) {
        app.fretboard.setScale(id)
        app.sheet = nil
    }

    /// «Т Т П Т Т Т П»: tones and semitones between the steps; other steps as «1½».
    static func steps(_ scale: Scale) -> String {
        let s = Array(Set(scale.degrees.map { (($0.semitones % 12) + 12) % 12 })).sorted()
        guard s.count > 1 else { return "" }
        let gaps = zip(s, s.dropFirst().map { $0 } + [12]).map { $1 - $0 }
        return gaps.map { gap in
            switch gap {
            case 1: return "П"
            case 2: return "Т"
            case 3: return "1½"
            default: return "\(Double(gap) / 2)".replacingOccurrences(of: ".0", with: "").replacingOccurrences(of: ".", with: ",")
            }
        }.joined(separator: " ")
    }
}

/// Row of the scale sheet (canvas: min 60 + padding 8 × 16 + border, gap 12, title 15 primary, subtitle 12, check 20 or › 16).
private struct ScaleRow<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let checked: Bool
    var showsChevron = true
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Typo.notes(title, size: 15).foregroundStyle(Theme.textPrimary)
                if let subtitle, !subtitle.isEmpty { Typo.notes(subtitle, size: 12).foregroundStyle(Theme.textTertiary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
            if checked {
                Icon(.check, size: 20, lineWidth: 2, color: Theme.textPrimary)
            } else if showsChevron {
                Icon(.chevronRight, size: 16, color: Theme.textTertiary)
            }
        }
        // Canvas (content-box): min-height 60 inside 8 pt padding, + the 1 pt border below = 77.
        .frame(minHeight: 60)
        .padding(.horizontal, 16).padding(.vertical, 8).padding(.bottom, 1)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
        .contentShape(Rectangle())
    }
}

extension ScaleRow where Trailing == EmptyView {
    init(title: String, subtitle: String?, checked: Bool, showsChevron: Bool = true) {
        self.init(title: title, subtitle: subtitle, checked: checked, showsChevron: showsChevron, trailing: { EmptyView() })
    }
}

/// Chip with a note name (canvas `<span>` chip: 32 pt + border, 12 medium; accidentals in the system font).
struct NoteChip: View {
    enum Style { case plain, selected, marked }
    let text: String
    var style: Style = .plain

    init(text: String, selected: Bool = false) { self.text = text; style = selected ? .selected : .plain }
    init(text: String, style: Style) { self.text = text; self.style = style }

    var body: some View {
        // Canvas: plain — white 5 % / 10 % ring, #e9e6df; selected — ivory 10 % / 55 %; marked (search) — 8 % / 40 %.
        let (fill, ring): (Double, Double) = switch style {
        case .plain: (0, 0)
        case .selected: (0.1, 0.55)
        case .marked: (0.08, 0.4)
        }
        Typo.notes(text, size: 12, weight: .medium)
            .foregroundStyle(style == .plain ? Theme.textBody : Theme.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 16).fill(style == .plain ? Theme.fill : Color(hex: 0xf6f3ec, opacity: fill)))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(style == .plain ? Theme.hairlineStrong : Color(hex: 0xf6f3ec, opacity: ring), lineWidth: 1))
            .fixedSize()
    }
}

/// «Вид и подписи» (canvas «Вид и подписи», top 180): labels on the notes, what to show (notes outside the scale,
/// frets counted from the capo, the capo), how the guitar is held; «Готово».
struct FretViewSheet: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let fretboard = app.fretboard
        DesignSheet(title: "Вид и подписи", height: 664, close: { app.sheet = nil }) {
            VStack(spacing: 14) {
                VStack(spacing: 0) {
                    SectionCaption(text: "Подписи на нотах")
                    Card {
                        Segments(options: [(LabelMode.notes, "Ноты"), (.degrees, "Ступени"), (.none, "Без подписей")],
                                 selection: Binding(get: { [.notes, .degrees, .none].contains(fretboard.settings.labels) ? fretboard.settings.labels : .notes },
                                                    set: { var s = fretboard.settings; s.labels = $0; fretboard.settings = s }))
                            .padding(6)
                    }
                }
                VStack(spacing: 0) {
                    SectionCaption(text: "Показывать")
                    Card {
                        CardRow(title: "Ноты вне гаммы", minHeight: 53) {
                            ToggleSwitch(isOn: Binding(get: { fretboard.showOutOfScale }, set: { fretboard.showOutOfScale = $0 }), label: "Ноты вне гаммы")
                        }
                        CardRow(title: "Лады от капо", subtitle: "номера считаются от капо", minHeight: 61) {
                            ToggleSwitch(isOn: Binding(get: { fretboard.fretsFromCapo }, set: { fretboard.fretsFromCapo = $0 }), label: "Лады от капо")
                        }
                        Menu {
                            Button("Без капо") { app.updateInstrument { $0.capo = 0 } }
                            ForEach(1...12, id: \.self) { fret in
                                Button("На \(fret)-м ладу") { app.updateInstrument { $0.capo = fret } }
                            }
                        } label: {
                            CardRow(title: "Капо", minHeight: 53) { valueChevron(capoText) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Капо: \(capoText)")
                    }
                }
                VStack(spacing: 0) {
                    SectionCaption(text: "Как держите гитару")
                    Card {
                        CardRow(title: "Для левши", subtitle: "гриф зеркально", minHeight: 61) {
                            ToggleSwitch(isOn: binding(\.leftHanded), label: "Для левши")
                        }
                        // In portrait the low string is on the left, mirrored for left-handers (the same setting).
                        Menu {
                            Button("Слева") { var s = fretboard.settings; s.leftHanded = false; fretboard.settings = s }
                            Button("Справа") { var s = fretboard.settings; s.leftHanded = true; fretboard.settings = s }
                        } label: {
                            CardRow(title: "Низкая струна", minHeight: 53) { valueChevron(fretboard.settings.leftHanded ? "справа" : "слева") }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Низкая струна: \(fretboard.settings.leftHanded ? "справа" : "слева")")
                    }
                }
            }
        } footer: {
            SheetButton(title: "Готово") { app.sheet = nil }
        }
    }

    private var capoText: String {
        let capo = app.instrument.capo
        return capo > 0 ? "на \(capo)-м ладу" : "нет"
    }

    private func valueChevron(_ text: String) -> some View {
        HStack(spacing: 8) {
            Text(text)
            Icon(.chevronRight, size: 16, color: Theme.textTertiary)
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<FretboardSettings, T>) -> Binding<T> {
        Binding(get: { app.fretboard.settings[keyPath: keyPath] },
                set: { var s = app.fretboard.settings; s[keyPath: keyPath] = $0; app.fretboard.settings = s })
    }
}

/// «Проигрывание» (canvas «Проигрывание», top 150): direction, pattern, tempo shared with the metronome, the click with
/// a one-bar count-in, loop, drone; «С проверкой» (FB-14) and «Играть» at the bottom.
struct FretPlaySheet: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        DesignSheet(title: "Проигрывание", height: 694, close: { app.sheet = nil }) {
            PlaybackControls()
        } footer: {
            Button {
                app.sheet = nil
                app.fretboard.startTraining()
            } label: {
                HStack(spacing: 8) {
                    Icon(.mic, size: 18, color: Theme.textBody)
                    Text("С проверкой").font(Typo.inter(15, .medium)).foregroundStyle(Theme.textBody).lineLimit(1)
                }
                .frame(width: 168, height: 52)
                .background(Capsule().fill(Theme.cardFill))
                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
            .accessibilityHint("Вы играете эти ноты по щелчку — микрофон проверяет время и высоту")
            Button {
                app.sheet = nil
                if !app.fretboard.isPlaying { app.fretboard.startPlayback() }
            } label: {
                HStack(spacing: 8) {
                    Icon(.play, size: 18, color: Theme.background)
                    Text("Играть").font(Typo.button).foregroundStyle(Theme.background)
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Capsule().fill(Theme.primaryFill))
            }
            .buttonStyle(PressableStyle())
        }
    }
}

/// Direction, pattern, tempo, click, loop and drone: the same in «Проигрывание» and in the path sheet.
struct PlaybackControls: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let fretboard = app.fretboard
        VStack(spacing: 14) {
            VStack(spacing: 0) {
                SectionCaption(text: "Направление")
                Card {
                    Segments(options: [(PlaybackDirection.up, "Вверх"), (.down, "Вниз"), (.upDown, "Вверх-вниз")],
                             selection: Binding(get: { fretboard.direction }, set: { fretboard.direction = $0 }))
                        .padding(6)
                }
            }
            VStack(spacing: 0) {
                SectionCaption(text: "Рисунок")
                Card {
                    Segments(options: [(PlaybackChoice.up, "Подряд"), (.thirds, "Терции"), (.seq3, "По 3"), (.seq4, "По 4")],
                             selection: Binding(get: { fretboard.playback }, set: { fretboard.playback = $0 }))
                        .padding(6)
                }
            }
            Card {
                CardRow(title: "Темп", subtitle: "общий с метрономом", minHeight: 61) {
                    ValueStepper(value: "\(Int(app.metronome.bpm))", canDecrement: app.metronome.bpm > 20, canIncrement: app.metronome.bpm < 400,
                                 decrement: { app.metronome.bpm -= 1 }, increment: { app.metronome.bpm += 1 })
                }
                CardRow(title: "Щелчок метронома", subtitle: "с отсчётом в один такт", minHeight: 61) {
                    ToggleSwitch(isOn: Binding(get: { fretboard.settings.clickWithPlayback },
                                               set: { var s = fretboard.settings; s.clickWithPlayback = $0; fretboard.settings = s }),
                                 label: "Щелчок метронома")
                }
                CardRow(title: "По кругу", minHeight: 53) {
                    ToggleSwitch(isOn: Binding(get: { fretboard.loop }, set: { fretboard.loop = $0 }), label: "По кругу")
                }
                CardRow(title: "Бурдон на тонике", subtitle: "\(app.formatter.string(fretboard.settings.tonic)) тянется, пока не выключите", minHeight: 61) {
                    ToggleSwitch(isOn: Binding(get: { fretboard.isDroning }, set: { $0 ? fretboard.startDrone() : fretboard.stopDrone() }),
                                 label: "Бурдон на тонике")
                }
            }
        }
    }
}
