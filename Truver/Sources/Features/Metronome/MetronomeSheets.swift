import SwiftUI
import TruverDSP

// Metronome sheets of the canvas. Heights are 844 − the panel's top on the canvas.

/// Canvas card of the metronome sheets (`Card` already keeps its rows inside the 1 pt border, as CSS does; the
/// rows' own border-bottom comes from `MetroRow`).
struct MetroCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        Card { content() }
    }
}

/// A canvas row (`display: flex; align-items: center; justify-content: space-between; padding: 0 16px; gap: 10px`):
/// title 15 body (one line — the trailing control never pushes it onto two), subtitle 12 tertiary 2 below, trailing
/// 14 secondary; `minHeight` is the canvas `min-height`, the divider adds its 1 pt below it.
struct MetroRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var showsDivider = true
    var minHeight: CGFloat = 56
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typo.row).foregroundStyle(Theme.textBody).lineLimit(1).fixedSize()
                if let subtitle { Text(subtitle).font(Typo.caption).foregroundStyle(Theme.textTertiary).lineLimit(2) }
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
            trailing().font(Typo.inter(14)).foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: minHeight)
        .padding(.bottom, showsDivider ? 1 : 0)
        .overlay(alignment: .bottom) {
            if showsDivider { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
        }
        .contentShape(Rectangle())
    }
}

extension MetroRow where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, showsDivider: Bool = true, minHeight: CGFloat = 56) {
        self.init(title: title, subtitle: subtitle, showsDivider: showsDivider, minHeight: minHeight, trailing: { EmptyView() })
    }
}

/// «Размер и деление» (canvas top 96): beats per bar and the beat value, groups as chips, the subdivision
/// «Нет 2 3 4», a preview of the strip. Swing and the second track moved to «Ритм» (♫) — the canvas sheet has none.
struct MeterSheet: View {
    @Environment(AppModel.self) private var app

    private var metronome: MetronomeController { app.metronome }

    var body: some View {
        let m = metronome.meter
        DesignSheet(title: "Размер и деление", height: 748, close: { app.sheet = nil }) {
            VStack(spacing: 14) {
                VStack(spacing: 0) {
                    SectionCaption(text: "Размер")
                    MetroCard {
                        MetroRow(title: "Долей в такте", minHeight: 60) {
                            ValueStepper(value: "\(m.numerator)", canDecrement: m.numerator > 1, canIncrement: m.numerator < 16,
                                         decrement: { setNumerator(m.numerator - 1) }, increment: { setNumerator(m.numerator + 1) })
                        }
                        MetroRow(title: "Длительность доли", minHeight: 60) {
                            Segments(options: [(4, "♩ 4"), (8, "♪ 8"), (16, "♬ 16")],
                                     selection: Binding(get: { m.denominator }, set: { var x = metronome.meter; x.denominator = $0; metronome.meter = x }),
                                     size: .compact)
                                .frame(width: 150)
                        }
                    }
                }
                VStack(spacing: 0) {
                    SectionCaption(text: "Группы")
                    MetroCard {
                        VStack(alignment: .leading, spacing: 10) {
                            FlowLayout(spacing: 6) {
                                ForEach(Self.groupings(m.numerator, current: m.grouping), id: \.self) { g in
                                    Button { setGrouping(g) } label: {
                                        Chip(text: g.map(String.init).joined(separator: "+"), style: m.grouping == g ? .emphasized : .plain)
                                    }
                                    .buttonStyle(PressableStyle())
                                }
                                Button { setGrouping(nil) } label: {
                                    Chip(text: "Без групп", style: (m.grouping?.count ?? 0) < 2 ? .emphasized : .plain)
                                }
                                .buttonStyle(PressableStyle())
                            }
                            Text(groupingError ?? "Сильные доли — с акцентом. Удобно для 7/8, 5/8, 9/8")
                                .font(Typo.caption).foregroundStyle(groupingError == nil ? Theme.textTertiary : Theme.danger)
                                .lineLimit(1).fixedSize()   // one line, as on the canvas
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                VStack(spacing: 0) {
                    SectionCaption(text: "Деление доли · щелчок между долями")
                    MetroCard {
                        // ME-3 1–9 and figures live in «Ритм» (♫); here the canvas offers none / 2 / 3 / 4.
                        Segments(options: [(1, "Нет"), (2, "2"), (3, "3"), (4, "4")],
                                 selection: Binding(get: { m.rhythm == nil || m.rhythm?.isPlain == true ? m.subdivision : 0 },
                                                    set: { var x = metronome.meter; x.subdivision = $0; x.rhythm = nil
                                                        if !x.isSwingAvailable { x.swing = 0.5 }
                                                        metronome.meter = x }),
                                 size: .compact)
                            .padding(6)
                    }
                }
                BeatStripPreview().padding(.horizontal, 2)
            }
        } footer: {
            SheetButton(title: "Готово") { app.sheet = nil }
        }
    }

    /// Groupings of 2s and 3s: ascending first (2+2+3), then descending (3+2+2), then the rest; at most three, plus
    /// the current one if it is another.
    static func groupings(_ n: Int, current: [Int]?) -> [[Int]] {
        var all: [[Int]] = []
        func build(_ left: Int, _ prefix: [Int]) {
            if left == 0 { if prefix.count > 1 { all.append(prefix) }; return }
            for part in [2, 3] where part <= left { build(left - part, prefix + [part]) }
        }
        if n <= 12 { build(n, []) }
        guard let fewest = all.map(\.count).min() else { return current.map { $0.count > 1 ? [$0] : [] } ?? [] }
        let asc = all.filter { $0.count == fewest }.map { $0.sorted() }.first!
        var result = [asc]
        if Array(asc.reversed()) != asc { result.append(Array(asc.reversed())) }
        for g in all.sorted(by: { $0.count < $1.count }) where !result.contains(g) && result.count < 3 { result.append(g) }
        if let current, current.count > 1, !result.contains(current) { result.append(current) }
        return result
    }

    private var groupingError: String? {
        let m = metronome.meter
        guard let grouping = m.grouping, grouping.count > 1, grouping.reduce(0, +) != m.numerator else { return nil }
        return "Сумма групп \(grouping.reduce(0, +)), а долей \(m.numerator)"
    }

    private func setGrouping(_ g: [Int]?) {
        var x = metronome.meter
        x.grouping = g
        x.accents = MeterSettings.defaultAccents(numerator: x.numerator, grouping: g)
        metronome.meter = x
    }

    private func setNumerator(_ value: Int) {
        var x = metronome.meter
        x.numerator = value
        if x.grouping?.reduce(0, +) != value { x.grouping = nil }
        x.accents = MeterSettings.defaultAccents(numerator: value, grouping: x.grouping)
        metronome.meter = x
    }
}

/// The beat strip under «Размер и деление» (same bars as the screen, the lit beat included).
struct BeatStripPreview: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.metronome.meter
        let sizes = (m.grouping?.reduce(0, +) == m.numerator ? m.grouping : nil) ?? [m.numerator]
        let starts = sizes.indices.map { sizes.prefix($0).reduce(0, +) }
        GeometryReader { proxy in
            let gaps = CGFloat(sizes.count - 1) * 14 + CGFloat(m.numerator - sizes.count) * 5
            let width = min(34, (proxy.size.width - gaps) / CGFloat(max(1, m.numerator)))
            HStack(alignment: .bottom, spacing: 14) {
                ForEach(Array(sizes.enumerated()), id: \.offset) { g, size in
                    HStack(alignment: .bottom, spacing: 5) {
                        ForEach(0..<size, id: \.self) { i in
                            let beat = starts[g] + i
                            let level = m.accents[safe: beat] ?? .normal
                            RoundedRectangle(cornerRadius: 3).fill(MetronomeScreen.barFill(level))
                                .frame(width: width, height: MetronomeScreen.barHeight(level))
                                .overlay {
                                    if app.metronome.litBeat == beat {
                                        RoundedRectangle(cornerRadius: 3).fill(Theme.beat)
                                            .shadow(color: Theme.beat.opacity(0.9), radius: 6)
                                            .shadow(color: Theme.beat.opacity(0.45), radius: 3)
                                    }
                                }
                        }
                    }
                }
            }
            .frame(width: proxy.size.width, height: 44, alignment: .bottom)
        }
        .frame(height: 44)
        .accessibilityHidden(true)
    }
}

/// Swing (ME-3) for «Ритм»: it was in «Размер и деление», which the canvas now draws without it.
struct SwingCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let metronome = app.metronome
        let m = metronome.meter
        MetroCard {
            // A rhythmic figure plays as drawn: swing does not apply to it (it was offered and ignored).
            let figure = (m.rhythm.map { !$0.isPlain } ?? false) || m.beatRhythms != nil
            MetroRow(title: "Свинг", subtitle: figure ? "Не действует при ритмической фигуре" : (m.isSwingAvailable ? nil : "Доступен при чётном делении"),
                    showsDivider: false) {
                if m.isSwingAvailable && !figure {
                    ValueStepper(value: "\(Int(((m.swing - 0.5) / 0.25 * 100).rounded())) %", canDecrement: m.swing > 0.5, canIncrement: m.swing < 0.75,
                                 decrement: { set(m.swing - 0.025) }, increment: { set(m.swing + 0.025) })
                } else {
                    Text("0 %")
                }
            }
        }
    }

    private func set(_ value: Double) {
        var x = app.metronome.meter
        x.swing = value.clamped(to: 0.5...0.75)
        app.metronome.meter = x
    }
}

/// «Режимы» (canvas top 150): one mode at a time — Обычный, Разгон (with its numbers), Тренировка пропусков,
/// Случайный пропуск, Карта песни; the other modes of the app follow under «Ещё режимы».
struct ModesSheet: View {
    @Environment(AppModel.self) private var app

    private var metronome: MetronomeController { app.metronome }

    var body: some View {
        let m = metronome.modes
        let choice = metronome.modeChoice
        DesignSheet(title: "Режимы", height: 694, close: { app.sheet = nil }) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 0) {
                    SectionCaption(text: "Один режим за раз")
                    MetroCard {
                        row(.normal, "Обычный", "темп не меняется", choice)
                        row(.speedUp, "Разгон", "темп растёт до цели", choice, params: .speedUp) {
                            if choice == .speedUp {
                                HStack(spacing: 8) {
                                    tile("От", "\(Int(m.start))")
                                    tile("До", "\(Int(m.target))")
                                    tile("Шаг", m.interval == .seconds ? "+\(Int(m.step)) · \(m.everySeconds) с" : "+\(Int(m.step)) · \(m.every) т.")
                                }
                                .padding(.top, 10)
                            }
                        }
                        row(.gapBars, "Тренировка пропусков", "играет \(m.gapOn) \(MetronomeController.bars(m.gapOn)), молчит \(m.gapOff)", choice, params: .gapBars)
                        row(.randomMute, "Случайный пропуск", "доли выпадают с вероятностью", choice, params: .randomMute)
                        row(.songMap, "Карта песни", "части со своим темпом и размером", choice, params: .songMap)
                    }
                }
                Text("Режим работает поверх размера и деления. Выключить — выбрать «Обычный».")
                    .font(Typo.caption).foregroundStyle(Theme.textTertiary).lineSpacing(16.8 - 14.52)
                    // gap 14 + padding 10 + the half-leading of line-height 1.4.
                    .padding(.horizontal, 4).padding(.top, 11.14)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 0) {
                    SectionCaption(text: "Ещё режимы")
                    MetroCard {
                        row(.twoForward, "Два вперёд, один назад", "\(Int(m.start)) → \(Int(m.target)) · N = \(Int(m.step))", choice, params: .twoForward)
                        row(.fastSlow, "Быстро / медленно", "чередование двух темпов", choice, params: .fastSlow)
                        row(.displaced, "Перенос щелчка", "только 2 и 4 / только «и» / только раз", choice, params: .displaced)
                        row(.ladder, "Лесенка делений", "1 → 2 → 3 → 4", choice, params: .ladder)
                    }
                }
                .padding(.top, 20)   // below the canvas content, under the footer until scrolled
            }
        } footer: {
            SheetButton(title: "Готово") { app.sheet = nil }
        }
    }

    private func row(_ mode: MetronomeController.ModeChoice, _ title: String, _ subtitle: String, _ choice: MetronomeController.ModeChoice,
                     params: ModeParamKind? = nil, @ViewBuilder extra: () -> some View = { EmptyView() }) -> some View {
        let selected = mode == choice
        return Button {
            if selected, let params { app.sheet = .metroModeParams(params); return }
            metronome.choose(mode)
            // Modes whose numbers are not on the row open their parameters.
            if let params, mode != .speedUp { app.sheet = .metroModeParams(params) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Typo.inter(15)).foregroundStyle(Theme.textPrimary)
                    Text(subtitle).font(Typo.caption).foregroundStyle(Theme.textTertiary)
                    extra()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if selected {
                    Icon(.check, size: 20, lineWidth: 2, color: Theme.textPrimary)
                } else {
                    Icon(.chevronRight, size: 16, color: Theme.textTertiary)
                }
            }
            // CSS content box: `min-height: 60` is the content's, padding 8 and the border-bottom come on top.
            .frame(minHeight: 60)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .padding(.bottom, 1)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// «От 142»: radius 12, white 5 %, padding 8 × 10, caption 11, value 17.
    private func tile(_ caption: String, _ value: String) -> some View {
        Button { app.sheet = .metroModeParams(.speedUp) } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(caption).font(Typo.inter(11)).foregroundStyle(Theme.textTertiary)
                Text(value).font(Typo.inter(17)).foregroundStyle(Theme.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
        }
        .buttonStyle(.plain)
    }
}

/// Mode parameters (canvas «Режим «Разгон» — параметры», top 200): steppers, «Готово» returns to the modes.
struct ModeParamsSheet: View {
    @Environment(AppModel.self) private var app
    let kind: ModeParamKind

    private var metronome: MetronomeController { app.metronome }

    @State private var savingSong = false
    @State private var songName = ""

    /// Canvas: «Карта песни» top 54, «Случайный пропуск» top 500; the others keep the «Разгон» sheet (top 200).
    private var height: CGFloat {
        switch kind {
        case .songMap: return 790
        case .randomMute: return 344
        default: return 644
        }
    }

    var body: some View {
        DesignSheet(title: title, height: height, close: { app.sheet = nil }) {
            if kind == .songMap {
                SongMapEditor()
            } else if kind == .randomMute {
                // Canvas: the card (row 68), then the note 13 / 1.4, 12 below.
                VStack(alignment: .leading, spacing: 0) {
                    MetroCard { rows }
                    if let note {
                        Text(note).font(Typo.inter(13)).foregroundStyle(Theme.textTertiary).lineSpacing(18.2 - 15.73)
                            .padding(.horizontal, 4).padding(.top, 13.24)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    MetroCard { rows }
                    if let note { Text(note).font(Typo.caption).foregroundStyle(Theme.textTertiary) }
                }
            }
        } footer: {
            if kind == .songMap {
                Button { songName = "Песня"; savingSong = true } label: {
                    Text("В пресет").font(Typo.inter(15, .medium)).foregroundStyle(Theme.textBody)
                        .frame(width: 130, height: 50)
                        .background(Capsule(style: .circular).fill(Theme.cardFill))
                        .overlay(Capsule(style: .circular).strokeBorder(Theme.hairline, lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
            }
            SheetButton(title: "Готово") { app.sheet = .metroModes }
        }
        .overlay {
            if savingSong {
                TextFieldAlert(title: "Имя пресета", text: $songName, cancel: { savingSong = false }, save: {
                    let t = songName.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty { metronome.savePreset(named: t) }
                    savingSong = false
                })
            }
        }
    }

    private var title: String {
        switch kind {
        case .speedUp: return "Разгон"
        case .twoForward: return "Два вперёд, один назад"
        case .fastSlow: return "Быстро / медленно"
        case .songMap: return "Карта песни"
        case .displaced: return "Перенос щелчка"
        case .gapBars: return "Пропадающие такты"
        case .randomMute: return "Случайный пропуск"
        case .ladder: return "Лесенка делений"
        }
    }

    private func update(_ change: (inout MetronomeModes) -> Void) {
        var m = metronome.modes
        change(&m)
        metronome.modes = m
    }

    @ViewBuilder private var rows: some View {
        let m = metronome.modes
        switch kind {
        case .speedUp, .twoForward:
            MetroRow(title: "Старт", subtitle: "BPM") {
                ValueStepper(value: "\(Int(m.start))", canDecrement: m.start > 20, canIncrement: m.start < m.target - 1,
                             decrement: { update { $0.start = max(20, $0.start - 1) } }, increment: { update { $0.start = min($0.target - 1, $0.start + 1) } })
            }
            MetroRow(title: "Цель", subtitle: "BPM") {
                ValueStepper(value: "\(Int(m.target))", canDecrement: m.target > m.start + 1, canIncrement: m.target < 400,
                             decrement: { update { $0.target = max($0.start + 1, $0.target - 1) } }, increment: { update { $0.target = min(400, $0.target + 1) } })
            }
            MetroRow(title: kind == .speedUp ? "Шаг" : "N", subtitle: "BPM") {
                ValueStepper(value: "+\(Int(m.step))", canDecrement: m.step > 1, canIncrement: m.step < 20,
                             decrement: { update { $0.step = max(1, $0.step - 1) } }, increment: { update { $0.step = min(20, $0.step + 1) } })
            }
            if kind == .speedUp {
                MetroRow(title: "Интервал") {
                    Segments(options: [(MetronomeModes.Interval.bars, "Такты"), (.seconds, "Секунды")],
                             selection: Binding(get: { m.interval }, set: { v in update { $0.interval = v } }), size: .compact)
                        .frame(width: 170)
                }
            }
            if kind == .speedUp && m.interval == .seconds {
                MetroRow(title: "Каждые", subtitle: "секунд", showsDivider: false) {
                    ValueStepper(value: "\(m.everySeconds)", canDecrement: m.everySeconds > 5, canIncrement: m.everySeconds < 300,
                                 decrement: { update { $0.everySeconds = max(5, $0.everySeconds - 5) } }, increment: { update { $0.everySeconds = min(300, $0.everySeconds + 5) } })
                }
            } else {
                MetroRow(title: "Каждые", subtitle: MetronomeController.bars(m.every), showsDivider: false) {
                    ValueStepper(value: "\(m.every)", canDecrement: m.every > 1, canIncrement: m.every < 32,
                                 decrement: { update { $0.every = max(1, $0.every - 1) } }, increment: { update { $0.every = min(32, $0.every + 1) } })
                }
            }
        case .fastSlow:
            MetroRow(title: "Медленно", subtitle: "BPM") {
                ValueStepper(value: "\(Int(m.start))", canDecrement: m.start > 20, canIncrement: m.start < 400,
                             decrement: { update { $0.start = max(20, $0.start - 1) } }, increment: { update { $0.start = min(400, $0.start + 1) } })
            }
            MetroRow(title: "Быстро", subtitle: "BPM") {
                ValueStepper(value: "\(Int(m.fast))", canDecrement: m.fast > 20, canIncrement: m.fast < 400,
                             decrement: { update { $0.fast = max(20, $0.fast - 1) } }, increment: { update { $0.fast = min(400, $0.fast + 1) } })
            }
            MetroRow(title: "Каждые", subtitle: MetronomeController.bars(m.fastSlowBars), showsDivider: false) {
                ValueStepper(value: "\(m.fastSlowBars)", canDecrement: m.fastSlowBars > 1, canIncrement: m.fastSlowBars < 32,
                             decrement: { update { $0.fastSlowBars -= 1 } }, increment: { update { $0.fastSlowBars += 1 } })
            }
        case .songMap:
            EmptyView()
        case .randomMute:
            MetroRow(title: "Вероятность пропуска", subtitle: "первая доля звучит всегда", minHeight: 68) {
                ValueStepper(value: "\(m.muteChance) %", canDecrement: m.muteChance > 5, canIncrement: m.muteChance < 90,
                             decrement: { update { $0.muteChance = max(5, $0.muteChance - 5) } }, increment: { update { $0.muteChance = min(90, $0.muteChance + 5) } })
            }
        case .displaced:
            ForEach([ClickPattern.backbeats, .offbeats, .downbeat], id: \.self) { pattern in
                RadioRow(title: metronome.patternTitle(pattern).capitalizedFirst, selected: m.pattern == pattern, showsDivider: pattern != .downbeat) {
                    update { $0.pattern = pattern }
                }
            }
        case .gapBars:
            MetroRow(title: "Со щелчком", subtitle: MetronomeController.bars(m.gapOn)) {
                ValueStepper(value: "\(m.gapOn)", canDecrement: m.gapOn > 1, canIncrement: m.gapOn < 8,
                             decrement: { update { $0.gapOn -= 1 } }, increment: { update { $0.gapOn += 1 } })
            }
            MetroRow(title: "Без щелчка", subtitle: MetronomeController.bars(m.gapOff), showsDivider: false) {
                ValueStepper(value: "\(m.gapOff)", canDecrement: m.gapOff > 1, canIncrement: m.gapOff < 8,
                             decrement: { update { $0.gapOff -= 1 } }, increment: { update { $0.gapOff += 1 } })
            }
        case .ladder:
            MetroRow(title: "Тактов на шаг", subtitle: "деления 1 → 2 → 3 → 4", showsDivider: false) {
                ValueStepper(value: "\(m.ladderBarsPerStep)", canDecrement: m.ladderBarsPerStep > 1, canIncrement: m.ladderBarsPerStep < 8,
                             decrement: { update { $0.ladderBarsPerStep -= 1 } }, increment: { update { $0.ladderBarsPerStep += 1 } })
            }
        }
    }

    /// «До цели — 10 шагов, примерно 3 минуты».
    private var note: String? {
        let m = metronome.modes
        if kind == .fastSlow { return "Темп меняется на границе такта. Начинается с медленного." }
        if kind == .songMap { return "Части сменяются на границе такта. Сохраните как пресет — получится песня для сет-листа; педаль ↑ ↓ листает пресеты." }
        if kind == .randomMute { return "Пропущенная доля молчит везде: звук, вспышка, вибрация." }
        guard kind == .speedUp || kind == .twoForward, m.target > m.start, m.step > 0 else { return nil }
        let steps = Int(((m.target - m.start) / m.step).rounded(.up))
        var seconds = 0.0
        for i in 0..<steps {
            let bpm = m.start + Double(i) * m.step
            if kind == .speedUp && m.interval == .seconds {
                seconds += Double(m.everySeconds)
            } else {
                seconds += Double(m.every * metronome.meter.numerator) * 60 / bpm
            }
        }
        if kind == .twoForward { seconds *= 1.5 }
        let minutes = max(1, Int((seconds / 60).rounded()))
        return "До цели — \(steps) \(Self.steps(steps)), примерно \(minutes) \(Self.minutes(minutes))"
    }

    static func steps(_ n: Int) -> String { plural(n, "шаг", "шага", "шагов") }
    static func minutes(_ n: Int) -> String { plural(n, "минута", "минуты", "минут") }

    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let n10 = n % 10, n100 = n % 100
        if n10 == 1 && n100 != 11 { return one }
        if (2...4).contains(n10) && !(12...14).contains(n100) { return few }
        return many
    }
}


/// «Пресеты» (canvas top 300; empty: 430): rows 60 pt, swipe left for «Переименовать» / «Удалить» (64 pt each),
/// «+ Сохранить текущий как пресет» under the list; while a row is open — the hint about undoing a deletion.
struct PresetsSheet: View {
    @Environment(AppModel.self) private var app
    @State private var naming: NamingTarget?
    @State private var name = ""
    @State private var openRow: UUID?

    enum NamingTarget: Equatable { case new, rename(UUID) }

    private var metronome: MetronomeController { app.metronome }

    var body: some View {
        let presets = metronome.state.presets
        DesignSheet(title: "Пресеты", height: presets.isEmpty ? 414 : 544, close: { app.sheet = nil }) {
            if presets.isEmpty {
                empty
            } else {
                VStack(spacing: 14) {
                    VStack(spacing: 0) {
                        SectionCaption(text: openRow == nil ? "Пресеты · размер, деление, режим и темп" : "Пресеты")
                        MetroCard {
                            ForEach(presets) { preset in
                                PresetSwipeRow(id: preset.id, open: $openRow,
                                               rename: { name = preset.name; naming = .rename(preset.id) },
                                               delete: { metronome.deletePresetUndoable(preset.id) }) { isOpen in
                                    Button {
                                        metronome.load(preset)
                                        app.sheet = nil
                                    } label: {
                                        HStack(spacing: 12) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(preset.name).font(Typo.inter(15)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                                                Text(metronome.presetSubtitle(preset)).font(Typo.caption).foregroundStyle(Theme.textTertiary).lineLimit(1)
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            Text("\(Int(preset.settings.bpm))").font(Typo.inter(15)).foregroundStyle(Theme.textSecondary)
                                            if !isOpen {
                                                Group {
                                                    if preset.id == metronome.state.currentPresetId {
                                                        Icon(.check, size: 20, lineWidth: 2, color: Theme.textPrimary)
                                                    } else {
                                                        Color.clear
                                                    }
                                                }
                                                .frame(width: 20, height: 20)
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                        .frame(height: 60)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    if openRow != nil {
                        Text("Свайп влево — переименовать или удалить. Удалённый можно вернуть: «Отменить» на 5 секунд.")
                            .font(Typo.caption).foregroundStyle(Theme.textTertiary).lineSpacing(16.8 - 14.52)
                            .padding(.horizontal, 4).padding(.top, 11.14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Button { startNaming() } label: {
                            HStack(spacing: 8) {
                                Icon(.plus, size: 16, color: Theme.textBody)
                                Text("Сохранить текущий как пресет").font(Typo.inter(15, .medium)).foregroundStyle(Theme.textBody)
                            }
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Capsule(style: .circular).fill(Theme.cardFill))
                            .overlay(Capsule(style: .circular).strokeBorder(Theme.hairline, lineWidth: 1))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let deleted = metronome.deletedPreset {
                HStack(spacing: 10) {
                    Icon(.trash, size: 16, color: Theme.textTertiary)
                    Text("«\(deleted.preset.name)» удалён").font(Typo.inter(13, .medium)).foregroundStyle(Theme.textBody).lineLimit(1)
                    Spacer(minLength: 8)
                    Button("Отменить") { metronome.undoDelete() }
                        .font(Typo.inter(13, .semibold)).foregroundStyle(Theme.textPrimary).buttonStyle(.plain)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: 0x26282d, opacity: 0.96)))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairlineStrong, lineWidth: 1))
                .shadow(color: .black.opacity(0.6), radius: 15, y: 14)
                .padding(.horizontal, 24).padding(.bottom, 40)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Motion.out(Motion.Duration.base), value: metronome.deletedPreset?.preset.id)
        .onAppear { if let id = metronome.debugOpenPreset { openRow = id } }
        .overlay {
            if let target = naming {
                TextFieldAlert(title: "Имя пресета", text: $name, cancel: { naming = nil }, save: {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        switch target {
                        case .new: metronome.savePreset(named: trimmed)
                        case .rename(let id): metronome.renamePreset(id, to: trimmed)
                        }
                    }
                    naming = nil
                    openRow = nil
                })
            }
        }
    }

    private func startNaming() {
        name = "\(metronome.meter.numerator)/\(metronome.meter.denominator)" + (metronome.meter.rhythm.map { " · " + BeatRhythms.name($0) } ?? "")
        naming = .new
    }

    /// «Пресетов пока нет»: the metronome icon in a 56 pt ring, title 17 semibold, text 13, the ivory button 18 below.
    private var empty: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                // A 56 pt CSS span with a 1 pt border outside its content box — 58 in all.
                Icon(.metronome, size: 24, color: Theme.textSecondary)
                    .frame(width: 58, height: 58)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                Text("Пресетов пока нет").font(Typo.inter(17, .semibold)).foregroundStyle(Theme.textPrimary)
                Text("Настройте темп, размер и режим — и сохраните, чтобы включать одним касанием")
                    .font(Typo.inter(13)).foregroundStyle(Theme.textSecondary).lineSpacing(18.2 - 15.73)
                    .padding(.vertical, 1.24)   // the half-leading of line-height 1.4
                    .multilineTextAlignment(.center).frame(maxWidth: 260)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 26).padding(.horizontal, 10).padding(.bottom, 10)
            .frame(maxWidth: .infinity)
            SheetButton(title: "Сохранить текущий как пресет") { startNaming() }
                .padding(.top, 18)
        }
    }
}

/// A preset row with swipe-left actions (canvas «Пресеты — свайп»): «Переименовать» #3a3d44 and «Удалить» #c9483e,
/// 64 pt each, icons only; the open row narrows to the space left of them.
struct PresetSwipeRow<Content: View>: View {
    let id: UUID
    @Binding var open: UUID?
    let rename: () -> Void
    let delete: () -> Void
    @ViewBuilder var content: (Bool) -> Content
    @GestureState private var drag: CGFloat = 0

    private let reveal: CGFloat = 128

    var body: some View {
        let isOpen = open == id
        let base: CGFloat = isOpen ? -reveal : 0
        let offset = min(0, max(-reveal, base + drag))
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Button(action: rename) {
                        ZStack {
                            Icon(.list, size: 18, color: Theme.textPrimary)
                            Circle().fill(Theme.background).frame(width: 3, height: 3).overlay(Circle().stroke(Theme.textPrimary, lineWidth: 1.2))
                                .offset(x: -2.25, y: -3.75)
                        }
                        .frame(width: 64).frame(maxHeight: .infinity).background(Color(hex: 0x3a3d44))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Переименовать")
                    Button { open = nil; delete() } label: {
                        Icon(.trash, size: 18, color: .white)
                            .frame(width: 64).frame(maxHeight: .infinity).background(Color(hex: 0xc9483e))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Удалить")
                }
                .opacity(offset < 0 ? 1 : 0)
                content(isOpen)
                    .frame(width: isOpen && drag == 0 ? proxy.size.width - reveal : proxy.size.width, alignment: .leading)
                    .background(Color(hex: 0x1a1c20).opacity(offset < 0 ? 1 : 0))
                    .offset(x: isOpen && drag == 0 ? 0 : offset)
            }
        }
        .frame(height: 60)
        .clipped()
        .padding(.bottom, 1)   // the row's border-bottom under its 60 pt
        .simultaneousGesture(
            DragGesture(minimumDistance: 14)
                .updating($drag) { value, state, _ in
                    if abs(value.translation.width) > abs(value.translation.height) { state = value.translation.width }
                }
                .onEnded { value in
                    withAnimation(Motion.out(Motion.Duration.base)) {
                        open = base + value.translation.width < -reveal / 2 ? id : nil
                    }
                }
        )
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
        .animation(Motion.out(Motion.Duration.base), value: open)
        .accessibilityActions {
            Button("Переименовать", action: rename)
            Button("Удалить", action: delete)
        }
    }
}

/// Row with swipe-left actions «Имя» (#4a5263) and «Удалить» (#e5483b), 92 pt each.
struct SwipeRow<Content: View>: View {
    let id: UUID
    @Binding var open: UUID?
    var showsDivider = true
    /// nil — only «Удалить» (92 pt).
    let rename: (() -> Void)?
    let delete: () -> Void
    @ViewBuilder var content: () -> Content
    @GestureState private var drag: CGFloat = 0

    var body: some View {
        let reveal: CGFloat = rename == nil ? 92 : 184
        let base: CGFloat = open == id ? -reveal : 0
        let offset = min(0, max(-reveal, base + drag))
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                if let rename { action("Имя", icon: .rename, color: Color(hex: 0x4a5263), perform: rename) }
                action("Удалить", icon: .trash, color: Color(hex: 0xe5483b), perform: { open = nil; delete() })
            }
            .opacity(offset < 0 ? 1 : 0)
            content()
                .background(Color(hex: 0x1a1c20).opacity(offset < 0 ? 1 : 0))
                .offset(x: offset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 14)
                        .updating($drag) { value, state, _ in
                            if abs(value.translation.width) > abs(value.translation.height) { state = value.translation.width }
                        }
                        .onEnded { value in
                            withAnimation(Motion.out(Motion.Duration.base)) {
                                open = base + value.translation.width < -reveal / 2 ? id : nil
                            }
                        }
                )
        }
        .clipped()
        .overlay(alignment: .bottom) { if showsDivider { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) } }
        .animation(Motion.out(Motion.Duration.base), value: open)
        .accessibilityActions {
            if let rename { Button("Переименовать", action: rename) }
            Button("Удалить", action: delete)
        }
    }

    private func action(_ title: String, icon: AppIcon, color: Color, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: 2) {
                Icon(icon, size: 18, color: .white)
                Text(title).font(Typo.caption).foregroundStyle(.white)
            }
            .frame(width: 92)
            .frame(maxHeight: .infinity)
            .background(color)
        }
        .buttonStyle(.plain)
    }
}


/// «Звуки и выход» (canvas top 230): the click set as chips, «Громкость акцента», vibration on the strong beat,
/// flash and output rows.
struct SoundsSheet: View {
    @Environment(AppModel.self) private var app
    @State private var choosingFlash = false
    @State private var confirmScreenFlash = false

    private var metronome: MetronomeController { app.metronome }

    var body: some View {
        let s = metronome.state
        DesignSheet(title: "Звуки и выход", height: 614, close: { app.sheet = nil }) {
            VStack(spacing: 14) {
                VStack(spacing: 0) {
                    SectionCaption(text: "Звук")
                    MetroCard {
                        FlowLayout(spacing: 6) {
                            ForEach(ClickSounds.Kind.allCases, id: \.self) { kind in
                                Button {
                                    var x = metronome.state
                                    x.sound = kind
                                    metronome.state = x
                                    app.audio.host.clickSound = kind
                                } label: {
                                    Chip(text: Self.title(kind), style: s.sound == kind ? .emphasized : .plain)
                                }
                                .buttonStyle(PressableStyle())
                                .accessibilityAddTraits(s.sound == kind ? .isSelected : [])
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                MetroCard {
                    VStack(spacing: 10) {
                        HStack {
                            Text("Громкость акцента").font(Typo.row).foregroundStyle(Theme.textBody)
                            Spacer()
                            Text(Self.db(s.accentDB)).font(Typo.inter(14)).foregroundStyle(Theme.textSecondary).monospacedDigit()
                        }
                        AccentSlider(value: Binding(get: { s.accentDB }, set: { v in
                            var x = metronome.state
                            x.accentDB = v
                            metronome.state = x
                            app.audio.host.accentDB = v
                        }))
                    }
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 14)
                }
                MetroCard {
                    #if os(iOS)
                    MetroRow(title: "Вибрация на сильной доле") {
                        ToggleSwitch(isOn: Binding(get: { app.settings.vibration }, set: { app.settings.vibration = $0 }), label: "Вибрация на сильной доле")
                    }
                    #endif
                    Button { choosingFlash = true } label: {
                        MetroRow(title: "Вспышка", minHeight: 52) {
                            HStack(spacing: 8) {
                                Text(Self.flashTitle(s.flash))
                                Icon(.chevronRight, size: 16, color: Theme.textTertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    Button { app.showSettings = true } label: {
                        MetroRow(title: "Выход", subtitle: "при наушниках — в наушники", minHeight: 60) {
                            HStack(spacing: 8) {
                                Text(app.audio.outputName)
                                Icon(.chevronRight, size: 16, color: Theme.textTertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        } footer: {
            SheetButton(title: "Готово") { app.sheet = nil }
        }
        .overlay {
            if choosingFlash {
                DesignAlert(title: "Вспышка", message: "Не больше 3 вспышек в секунду",
                            actions: [FlashTarget.off, .strip, .screen].map { target in
                                .init(title: Self.flashTitle(target), role: s.flash == target ? .preferred : .normal) {
                                    choosingFlash = false
                                    if target == .screen { confirmScreenFlash = true } else { var x = metronome.state; x.flash = target; metronome.state = x }
                                }
                            },
                            dismiss: { choosingFlash = false })
            }
        }
        .alert("Вспышка на весь экран", isPresented: $confirmScreenFlash) {
            Button("Включить") { var x = metronome.state; x.flash = .screen; metronome.state = x }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Экран будет мигать в такт — не больше 3 раз в секунду. Если у вас светочувствительность, оставьте вспышку на полосе долей.")
        }
    }

    static func title(_ kind: ClickSounds.Kind) -> String {
        switch kind {
        case .click: return "Щелчок"
        case .wood: return "Дерево"
        case .electronic: return "Бип"
        case .hiHat: return "Хай-хэт"
        case .voice: return "Голос"
        }
    }

    static func flashTitle(_ target: FlashTarget) -> String {
        switch target {
        case .off: return "Выкл"
        case .strip: return "Полоса долей"
        case .screen: return "Весь экран"
        }
    }

    /// «+6 дБ», «0 дБ», «−3 дБ».
    static func db(_ value: Double) -> String {
        let n = Int(value.rounded())
        return (n > 0 ? "+\(n)" : (n < 0 ? "−\(-n)" : "0")) + " дБ"
    }
}

/// «Громкость акцента» slider of the canvas: 4 pt track (white 12 %), ivory fill, 28 pt white thumb; −3…+17 dB in
/// 1 dB steps (+6 sits at 45 %).
struct AccentSlider: View {
    @Binding var value: Double
    static let range: ClosedRange<Double> = -3...17

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let f = (value - Self.range.lowerBound) / (Self.range.upperBound - Self.range.lowerBound)
            ZStack(alignment: .topLeading) {
                Capsule().fill(Color.white.opacity(0.12)).frame(height: 4).offset(y: 12)
                Capsule().fill(Theme.accent).frame(width: w * f, height: 4).offset(y: 12)
                Circle().fill(Color.white).frame(width: 28, height: 28)
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
                    .offset(x: w * f - 14)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let x = (g.location.x / max(1, w)).clamped(to: 0...1)
                value = (Self.range.lowerBound + x * (Self.range.upperBound - Self.range.lowerBound)).rounded()
            })
        }
        .frame(height: 28)
        .accessibilityElement()
        .accessibilityLabel("Громкость акцента")
        .accessibilityValue(SoundsSheet.db(value))
        .accessibilityAdjustableAction { direction in
            value = (value + (direction == .increment ? 1 : -1)).clamped(to: Self.range)
        }
    }
}

/// «Таймер занятия» (canvas top 520): «Остановить через 20 мин» with a switch, «Минут» — 5 10 20 30 45 «…».
struct TimerSheet: View {
    @Environment(AppModel.self) private var app
    @State private var custom = false
    @State private var customText = ""

    private var metronome: MetronomeController { app.metronome }
    private static let presets = [5, 10, 20, 30, 45]

    var body: some View {
        let s = metronome.state
        DesignSheet(title: "Таймер занятия", height: 324, close: { app.sheet = nil }) {
            VStack(alignment: .leading, spacing: 0) {
                MetroCard {
                    MetroRow(title: "Остановить через \(s.timerMinutes) мин", subtitle: "сигнал, такт доигрывается", minHeight: 60) {
                        ToggleSwitch(isOn: Binding(get: { s.timerEnabled }, set: { v in var x = metronome.state; x.timerEnabled = v; metronome.state = x }),
                                     label: "Таймер занятия")
                    }
                }
                SectionCaption(text: "Минут").padding(.top, 12)
                HStack(spacing: 6) {
                    ForEach(Self.presets, id: \.self) { minutes in
                        cell("\(minutes)", selected: s.timerMinutes == minutes) { set(minutes: minutes) }
                    }
                    cell("…", selected: !Self.presets.contains(s.timerMinutes)) {
                        customText = "\(s.timerMinutes)"
                        custom = true
                    }
                }
            }
        }
        .overlay {
            if custom {
                TextFieldAlert(title: "Минут, от 1 до 180", text: $customText, cancel: { custom = false }, save: {
                    if let n = Int(customText.trimmingCharacters(in: .whitespaces)) { set(minutes: n) }
                    custom = false
                })
            }
        }
    }

    /// 40 pt capsule, 14 medium; the chosen one has an ivory ring.
    private func cell(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(Typo.inter(14, .medium)).foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(Capsule(style: .circular).fill(Color.white.opacity(selected ? 0.1 : 0.05)))
                .overlay(Capsule(style: .circular).strokeBorder(selected ? Theme.selectedBorder : Theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(text == "…" ? "Другое время" : "\(text) минут")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func set(minutes: Int) {
        var x = metronome.state
        x.timerMinutes = minutes.clamped(to: 1...180)
        x.timerEnabled = true
        metronome.state = x
    }
}

/// Wrapping row of chips (flex-wrap).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}


/// «Карта песни» (canvas top 54): count-in and loop, parts as cards (≡ drag handle, number, name, meter chip,
/// delete; tempo and length steppers), «+ Часть». The list sits in a 560 pt window that fades at the bottom.
struct SongMapEditor: View {
    @Environment(AppModel.self) private var app
    @State private var renaming: UUID?
    @State private var name = ""
    @State private var dragging: UUID?
    @State private var dragOffset: CGFloat = 0

    private var metronome: MetronomeController { app.metronome }
    private static let meters: [Meter] = [Meter(2, 4), Meter(3, 4), Meter(4, 4), Meter(5, 4), Meter(6, 8), Meter(7, 8), Meter(9, 8), Meter(12, 8), Meter(5, 8), Meter(11, 8), Meter(13, 16)]
    /// A part card is 10 + 36 + 6 + 36 + 2 + 13 + 12 pt tall plus 2 for the border, 10 apart.
    private static let partStride: CGFloat = 155

    struct Meter: Hashable, CustomStringConvertible {
        let n: Int, d: Int
        init(_ n: Int, _ d: Int) { self.n = n; self.d = d }
        var description: String { "\(n)/\(d)" }
    }

    var body: some View {
        let song = metronome.modes.song
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                MetroCard {
                    MetroRow(title: "Отсчёт", subtitle: "такт перед первой частью") {
                        ToggleSwitch(isOn: Binding(get: { metronome.modes.songCountIn }, set: { v in update { $0.songCountIn = v } }), label: "Отсчёт")
                    }
                    MetroRow(title: "По кругу", subtitle: "иначе в конце — стоп") {
                        ToggleSwitch(isOn: Binding(get: { metronome.modes.songLoop }, set: { v in update { $0.songLoop = v } }), label: "По кругу")
                    }
                }
                Text("Части · сменяются на границе такта · ≡ — перетащить")
                    .font(Typo.caption).foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 4).padding(.top, 4)
                ForEach(Array(song.enumerated()), id: \.element.id) { index, part in
                    partCard(index, part, count: song.count)
                        .offset(y: dragging == part.id ? dragOffset : 0)
                        .zIndex(dragging == part.id ? 1 : 0)
                }
                Button {
                    update { m in
                        var next = m.song.last ?? SongSection(name: "Часть", bpm: 120)
                        next.id = UUID()
                        next.name = "Часть \(m.song.count + 1)"
                        m.song.append(next)
                    }
                } label: { Chip(text: "+ Часть") }
                .buttonStyle(PressableStyle())
            }
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .frame(height: 560)
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [Color(hex: 0x0d0e10, opacity: 0), Theme.panel], startPoint: .top, endPoint: .bottom)
                .frame(height: 40).allowsHitTesting(false)
        }
        .overlay {
            if renaming != nil {
                TextFieldAlert(title: "Название части", text: $name, cancel: { renaming = nil }, save: {
                    let t = name.trimmingCharacters(in: .whitespaces)
                    if let id = renaming, !t.isEmpty { update { m in if let i = m.song.firstIndex(where: { $0.id == id }) { m.song[i].name = t } } }
                    renaming = nil
                })
            }
        }
    }

    private func partCard(_ index: Int, _ part: SongSection, count: Int) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("≡").font(Typo.inter(18)).foregroundStyle(Theme.textTertiary).frame(width: 18, height: 36)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                        .onChanged { g in dragging = part.id; dragOffset = g.translation.height }
                        .onEnded { g in
                            let shift = Int((g.translation.height / Self.partStride).rounded())
                            let target = (index + shift).clamped(to: 0...(count - 1))
                            dragging = nil
                            dragOffset = 0
                            if target != index { update { m in let p = m.song.remove(at: index); m.song.insert(p, at: target) } }
                        })
                    .accessibilityLabel("Перетащить")
                    .accessibilityActions {
                        if index > 0 { Button("Выше") { update { $0.song.swapAt(index, index - 1) } } }
                        if index < count - 1 { Button("Ниже") { update { $0.song.swapAt(index, index + 1) } } }
                    }
                Text("\(index + 1)").font(Typo.inter(13)).foregroundStyle(Theme.textTertiary).frame(width: 12, alignment: .leading)
                Button { name = part.name; renaming = part.id } label: {
                    Text(part.name).font(Typo.inter(16, .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                Menu {
                    ForEach(Self.meters, id: \.self) { meter in
                        Button(meter.description) { set(index) { $0.numerator = meter.n; $0.denominator = meter.d } }
                    }
                } label: {
                    HeaderChip(text: "\(part.numerator)/\(part.denominator)", icon: .chevronDown, iconSize: 12)
                }
                .accessibilityLabel("Размер \(part.numerator)/\(part.denominator)")
                if count > 1 {
                    RoundIconButton(icon: .trash, size: 36, iconSize: 16, label: "Удалить часть") {
                        update { $0.song.remove(at: index) }
                    }
                }
            }
            .frame(height: 36)
            HStack(alignment: .top) {
                VStack(spacing: 2) {
                    ValueStepper(value: "\(Int(part.bpm))", canDecrement: part.bpm > 20, canIncrement: part.bpm < 400,
                                 decrement: { set(index) { $0.bpm = max(20, $0.bpm - 1) } }, increment: { set(index) { $0.bpm = min(400, $0.bpm + 1) } })
                    Text("BPM").font(Typo.inter(11)).foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 8)
                VStack(spacing: 2) {
                    ValueStepper(value: "\(part.bars)", canDecrement: part.bars > 1, canIncrement: part.bars < 128,
                                 decrement: { set(index) { $0.bars -= 1 } }, increment: { set(index) { $0.bars += 1 } })
                    Text(MetronomeController.bars(part.bars)).font(Typo.inter(11)).foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 13).padding(.top, 11).padding(.bottom, 13)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private func set(_ index: Int, _ change: (inout SongSection) -> Void) {
        update { m in if m.song.indices.contains(index) { change(&m.song[index]) } }
    }

    private func update(_ change: (inout MetronomeModes) -> Void) {
        var m = metronome.modes
        change(&m)
        metronome.modes = m
    }
}

/// ME-8 «Вторая дорожка» in «Размер и деление»: none, polyrhythm (N even pulses per bar) or polymeter (a click
/// every N beats across bar lines), its own bell sound.
struct PolyTrackSection: View {
    @Environment(AppModel.self) private var app

    private var metronome: MetronomeController { app.metronome }

    private enum Choice: Hashable { case none, rhythm, meter }

    var body: some View {
        let m = metronome.meter
        let poly = m.poly
        VStack(alignment: .leading, spacing: 8) {
            Text("Вторая дорожка").font(Typo.caption).foregroundStyle(Theme.textTertiary)
            Segments(options: [(Choice.none, "Нет"), (.rhythm, "Полиритм"), (.meter, "Полиметр")],
                     selection: Binding(get: { poly.map { $0.kind == .rhythm ? .rhythm : .meter } ?? .none },
                                        set: { choice in
                                            var x = metronome.meter
                                            switch choice {
                                            case .none: x.poly = nil
                                            case .rhythm: x.poly = PolyTrack(kind: .rhythm, count: x.numerator == 3 ? 2 : 3)
                                            case .meter: x.poly = PolyTrack(kind: .meter, count: x.numerator == 3 ? 4 : 3)
                                            }
                                            metronome.meter = x
                                        }),
                     size: .compact)
            if let poly {
                MetroCard {
                    MetroRow(title: poly.kind == .rhythm ? "\(poly.count) против \(m.numerator)" : "\(poly.count)/\(m.denominator) против \(m.numerator)/\(m.denominator)",
                            subtitle: poly.kind == .rhythm ? "ровных ударов на такт, свой звук" : "щелчок каждые \(poly.count) доли, сходятся через \(lcm(poly.count, m.numerator))",
                            showsDivider: false) {
                        ValueStepper(value: "\(poly.count)", canDecrement: poly.count > 2, canIncrement: poly.count < 16,
                                     decrement: { setCount(poly.count - 1) }, increment: { setCount(poly.count + 1) })
                    }
                }
            }
        }
    }

    private func setCount(_ n: Int) {
        var x = metronome.meter
        x.poly?.count = n
        metronome.meter = x
    }

    private func lcm(_ a: Int, _ b: Int) -> Int {
        func gcd(_ x: Int, _ y: Int) -> Int { y == 0 ? x : gcd(y, x % y) }
        return a / max(1, gcd(a, b)) * b
    }
}
