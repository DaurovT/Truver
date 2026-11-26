import SwiftUI
import TruverDSP

/// Panel under the controls while «Проверка игры» is on (in place of Tap): the last notes as dots on a
/// rushed ← 0 → dragged line, coloured by grade, and the last bar in one line (SM-3).
struct PlayCheckPanel: View {
    @Environment(AppModel.self) private var app
    var height: CGFloat = 60

    private var check: PlayCheckController { app.playCheck }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack {
                    Capsule().fill(Color.white.opacity(0.06)).frame(height: 4)
                    Rectangle().fill(Theme.textTertiary).frame(width: 1.5, height: 18)
                    ForEach(Array(check.recent.enumerated()), id: \.offset) { index, note in
                        if let x = position(note, width: w) {
                            Circle().fill(color(note.grade))
                                .frame(width: 10, height: 10)
                                .opacity(0.25 + 0.75 * Double(index + 1) / Double(max(1, check.recent.count)))
                                .offset(x: x)
                        }
                    }
                }
                .frame(width: w, height: 20)
                .overlay(alignment: .bottomLeading) { Text("раньше").font(Typo.inter(9)).foregroundStyle(Theme.textTertiary).offset(y: 10) }
                .overlay(alignment: .bottomTrailing) { Text("позже").font(Typo.inter(9)).foregroundStyle(Theme.textTertiary).offset(y: 10) }
            }
            .frame(height: 20)
            .padding(.bottom, 4)
            Text(line).font(Typo.inter(13)).foregroundStyle(Theme.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: height)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Проверка игры")
        .accessibilityValue(line)
    }

    /// ±half the subdivision spans the width; missing / extra notes sit at the edges.
    private func position(_ note: GradedNote, width: CGFloat) -> CGFloat? {
        guard let e = note.expected else { return nil }
        guard let d = note.deviation else { return note.grade == .missing ? -width / 2 + 5 : nil }
        let x = CGFloat(d / (e.interval / 2)).clamped(to: -1...1)
        return x * (width / 2 - 5)
    }

    private func color(_ grade: RhythmGrade) -> Color {
        switch grade {
        case .exact: return Theme.inTune
        case .good: return Theme.textPrimary
        case .inaccurate: return Theme.flat
        case .off, .extra, .missing: return Theme.sharp
        case .unrecognized: return Theme.textTertiary
        }
    }

    private var line: String {
        if check.gradingUnavailable { return "Деление короче 40 мс — оценка ритма недоступна" }
        let m = app.metronome
        // Step by step: what to do now (user: «не до конца понятно, как это работает»).
        if !m.isPlaying { return "Нажмите ▶ · такт отсчёта · потом играйте \(PlayCheckSheet.whatToPlay(m.meter, short: true))" }
        if m.currentBar == 0 && check.lastBar == nil { return "Отсчёт — слушайте этот такт, играть со следующего" }
        if check.idle { return "Не слышу игры — играйте \(PlayCheckSheet.whatToPlay(m.meter, short: true))" }
        guard let bar = check.lastBar else { return "Играйте \(PlayCheckSheet.whatToPlay(m.meter, short: true)) · оценка после такта" }
        if !bar.isCounted { return "Такт \(bar.bar) не засчитан — много нераспознанных нот" }
        let share = Int((bar.accurateShare * 100).rounded())
        var parts = ["Такт \(bar.bar) · \(share) %"]
        if let m = bar.meanDeviation {
            let ms = Int((m * 1000).rounded())
            parts.append(ms == 0 ? "ровно" : (ms < 0 ? "спешите \(-ms) мс" : "тянете \(ms) мс"))
        }
        if let s = bar.spread { parts.append("разброс \(Int((s * 1000).rounded())) мс") }
        if bar.missing > 0 { parts.append("пропусков \(bar.missing)") }
        return parts.joined(separator: " · ")
    }
}

/// «Проверка игры» settings: on / off, source hint (SM-7), tempo by result (SM-8), the ceiling (SM-9).
struct PlayCheckSheet: View {
    @Environment(AppModel.self) private var app

    private var check: PlayCheckController { app.playCheck }

    /// What one plays so that every attack has its click: the subdivision or the figure.
    static func whatToPlay(_ m: MeterSettings, short: Bool) -> String {
        if let r = m.rhythm, !r.isPlain {
            return short ? "по рисунку «\(BeatRhythms.name(r))»" : "по рисунку «\(BeatRhythms.name(r))» — нота на каждый щелчок фигуры"
        }
        let n = m.subdivision
        let name: String
        switch n {
        case 1: name = "четвертями"
        case 2: name = "восьмыми"
        case 3: name = "триолями"
        case 4: name = "шестнадцатыми"
        case 6: name = "секстолями"
        default: name = "по \(n) на долю"
        }
        if short { return name }
        return n == 1 ? "четвертями — одна нота на каждый щелчок" : "\(name) — \(n) ноты на каждую долю, на каждый щелчок"
    }

    @State private var showingHelp = false

    /// Canvas «Проверка игры» (top 168): what to play and the legend, tempo by result, calibration, «Как это работает».
    var body: some View {
        DesignSheet(title: "Проверка игры", height: 676, close: { app.sheet = nil }) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Играйте по ноте на щелчок. После такта — точки: левее — раньше, правее — позже.")
                        .font(Typo.inter(15)).foregroundStyle(Theme.textBody).lineSpacing(21 - 18.15)
                        .padding(.vertical, 1.43)   // the half-leading of line-height 1.4 above and below
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 14) {
                        legend(Theme.inTune, "точно")
                        legend(Theme.textPrimary, "хорошо")
                        legend(Theme.flat, "неточно")
                        legend(Theme.sharp, "мимо")
                    }
                }
                .padding(.horizontal, 17).padding(.vertical, 15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.cardFill))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairline, lineWidth: 1))
                MetroCard {
                    MetroRow(title: "Темп по результату", subtitle: "\(check.settings.cleanBars) \(Self.clean(check.settings.cleanBars)) — быстрее", minHeight: 58) {
                        ToggleSwitch(isOn: Binding(get: { check.settings.adaptive }, set: { check.settings.adaptive = $0 }), label: "Темп по результату")
                    }
                    MetroRow(title: "Шаг", subtitle: "BPM") {
                        ValueStepper(value: "\(check.settings.step)", canDecrement: check.settings.step > 1, canIncrement: check.settings.step < 20,
                                     decrement: { check.settings.step -= 1 }, increment: { check.settings.step += 1 })
                    }
                    MetroRow(title: "Тактов для шага") {
                        ValueStepper(value: "\(check.settings.cleanBars)", canDecrement: check.settings.cleanBars > 1, canIncrement: check.settings.cleanBars < 16,
                                     decrement: { check.settings.cleanBars -= 1 }, increment: { check.settings.cleanBars += 1 })
                    }
                }
                MetroCard {
                    Button { Task { await check.calibrate() } } label: {
                        MetroRow(title: "Калибровка задержки", subtitle: calibrationText, minHeight: 58) {
                            HStack(spacing: 8) {
                                if case .running(let p) = check.calibration {
                                    ProgressView(value: p).tint(Theme.textPrimary).frame(width: 80)
                                } else if check.routeOffset != 0 {
                                    Text("\(check.routeOffset > 0 ? "+" : "−")\(Int((abs(check.routeOffset) * 1000).rounded())) мс").monospacedDigit()
                                }
                                Icon(.chevronRight, size: 16, color: Theme.textTertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    Button { showingHelp = true } label: {
                        MetroRow(title: "Как это работает", minHeight: 52) {
                            Icon(.chevronRight, size: 16, color: Theme.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if let c = check.ceiling {
                    Text("Потолок этого пресета: \(Int(c)) BPM · следующее занятие начнётся с \(Int(AdaptiveTempo.nextSessionStart(ceiling: c)))")
                        .font(Typo.caption).foregroundStyle(Theme.textSecondary)
                }
                if app.metronome.state.modes.tempo != .none {
                    Text("Режим темпа «\(MetronomeModes.title(app.metronome.state.modes.tempo))» ведёт темп сам — «Темп по результату» на это время выключен")
                        .font(Typo.caption).foregroundStyle(Theme.sharp)
                }
            }
        } footer: {
            SheetButton(title: check.isOn ? "Выключить проверку" : "Включить проверку", icon: .mic) {
                check.toggle()
                app.sheet = nil
            }
        }
        .overlay {
            if showingHelp {
                DesignAlert(title: "Как это работает", message: help, actions: [.init(title: "Понятно", role: .preferred) { showingHelp = false }],
                            dismiss: { showingHelp = false })
            }
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(text).font(Typo.caption).foregroundStyle(Theme.textSecondary)
        }
    }

    /// The steps that were on this sheet before the canvas fix, now behind «Как это работает».
    private var help: String {
        ["1. Включите проверку и нажмите ▶. Первый такт — отсчёт, слушайте.",
         "2. Играйте " + Self.whatToPlay(app.metronome.meter, short: false) + ".",
         "3. После каждого такта — оценка: точки левее — раньше щелчка, правее — позже. Зелёная — точно, белая — хорошо, синяя — неточно, оранжевая — мимо или пропуск.",
         "4. Стоп — итог: сколько точно, спешите или тянете, слабая доля.",
         "С наушниками или интерфейсом точнее: щелчок из динамика тоже попадает в микрофон. Через динамик первый такт — отсчёт, приложение запоминает щелчок.",
         "Темп по результату: \(check.settings.cleanBars) чистых такта (≥ 90 %) — быстрее, 2 такта < 70 % — медленнее."].joined(separator: "\n\n")
    }

    /// «1 чистый такт», «4 чистых такта», «5 чистых тактов».
    static func clean(_ n: Int) -> String {
        ModeParamsSheet.plural(n, "чистый такт", "чистых такта", "чистых тактов")
    }
}

extension PlayCheckSheet {
    /// SM-6 states: «Нужна тишина» → progress → value / «Слишком шумно» / «Щелчки не слышны».
    var calibrationText: String {
        switch app.playCheck.calibration {
        case .idle: return "через динамик — один раз"
        case .running: return "Нужна тишина… слушаю щелчки"
        case .done(let v): return "Готово: \(v >= 0 ? "+" : "−")\(Int((abs(v) * 1000).rounded())) мс для этой связки входа и выхода"
        case .failed(let why): return why
        }
    }
}

/// PL-3 «Итог попытки»: time, tempo and the ceiling, accuracy, rushing / dragging, the weakest beat.
struct PlayCheckSummarySheet: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        DesignSheet(title: "Итог попытки", height: 560, close: { app.sheet = nil }) {
            if let a = app.playCheck.summary {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        StatCard(caption: "Точно + хорошо", value: "\(Int((a.accurateShare * 100).rounded())) %")
                        StatCard(caption: "Темп", value: a.startBPM == a.endBPM ? "\(Int(a.endBPM))" : "\(Int(a.startBPM))→\(Int(a.endBPM))")
                    }
                    MetroCard {
                        MetroRow(title: "Время", subtitle: "\(a.bars) \(MetronomeController.bars(a.bars)) засчитано") {
                            Text(Self.clock(a.seconds)).monospacedDigit()
                        }
                        MetroRow(title: a.meanDeviation < 0 ? "Спешите" : "Тянете", subtitle: "среднее отклонение") {
                            Text("\(Int(abs(a.meanDeviation).rounded())) мс").monospacedDigit()
                        }
                        MetroRow(title: "Разброс", subtitle: "насколько ровно") {
                            Text("\(Int(a.spread.rounded())) мс").monospacedDigit()
                        }
                        if let beat = a.weakestBeat, let d = a.weakestBeatDeviation {
                            MetroRow(title: "Слабое место", subtitle: "доля \(beat + 1)") {
                                Text((d < 0 ? "спешите " : "тянете ") + "\(Int(abs(d).rounded())) мс").monospacedDigit()
                            }
                        }
                        if let drift = a.silenceDrift {
                            MetroRow(title: "Уход за тишину", subtitle: "первые ноты после возврата щелчка") {
                                Text("\(drift < 0 ? "−" : "+")\(Int(abs(drift).rounded())) мс").monospacedDigit()
                            }
                        }
                        MetroRow(title: "Потолок темпа", showsDivider: false) {
                            Text(a.ceiling.map { "\(Int($0)) BPM" } ?? "—").monospacedDigit()
                        }
                    }
                }
            }
        } footer: {
            SheetButton(title: "Готово") { app.sheet = nil }
        }
    }

    static func clock(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
}
