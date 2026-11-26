import SwiftUI
import TruverDSP

/// PL-2 «Занятие» (corrected canvas «Занятие — план» / «Занятие — идёт»): the plan editor with the total in the header,
/// the running exercise with a progress ring, the metronome's beats, tempo / meter / play-check chips, what comes next
/// and a big pause button between «Закончить» and «Дальше»; the summary (PL-3 per exercise).
struct PracticeSessionView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    private var session: PracticeSessionController { app.session }

    var body: some View {
        VStack(spacing: 0) {
            PracticePageHeader(icon: session.phase == .idle || session.isRunning ? .chevronLeft : .close,
                               label: session.phase == .idle || session.isRunning ? "Назад" : "Закрыть",
                               title: "Занятие", subtitle: subtitle, action: close)
            switch session.phase {
            case .idle: editor
            case .playing, .pause: running
            case .done: summary
            }
        }
        .background(ScreenBackground())
        .preferredColorScheme(.dark)
        .onAppear { session.applyDebugArguments() }
    }

    private func close() {
        session.stop()
        if session.phase == .done { session.reset() }
        dismiss()
    }

    private var subtitle: String {
        switch session.phase {
        case .idle:
            let n = session.plan.steps.count
            return "всего \(totalMinutes) мин · \(n) \(ModeParamsSheet.plural(n, "упражнение", "упражнения", "упражнений"))"
        case .playing:
            return "\(session.stepIndex + 1) из \(session.plan.steps.count) · \(session.currentStep.map(session.title) ?? "")"
        case .pause:
            return "пауза · дальше \(session.stepIndex + 1) из \(session.plan.steps.count)"
        case .done:
            return "занятие закончено"
        }
    }

    // MARK: Plan (PL-1, PL-2)

    private var editor: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(session.plan.steps.enumerated()), id: \.element.id) { index, step in
                        stepCard(index, step)
                    }
                    Button {
                        var p = session.plan
                        p.steps.append(p.steps.last.map { var s = $0; s.id = UUID(); return s } ?? PracticeStep())
                        session.plan = p
                    } label: { Chip(text: "+ Упражнение") }
                    .buttonStyle(PressableStyle())
                    VStack(spacing: 0) {
                        SectionCaption(text: "Между упражнениями")
                        Card {
                            PracticeRow(title: "Пауза", subtitle: "между упражнениями") {
                                ValueStepper(value: "\(session.plan.pauseSeconds) с", canDecrement: session.plan.pauseSeconds > 0,
                                             canIncrement: session.plan.pauseSeconds < 300,
                                             decrement: { session.plan.pauseSeconds = max(0, session.plan.pauseSeconds - 10) },
                                             increment: { session.plan.pauseSeconds = min(300, session.plan.pauseSeconds + 10) })
                            }
                            PracticeRow(title: "Голосовые подсказки", subtitle: "что дальше и сколько осталось") {
                                ToggleSwitch(isOn: Binding(get: { session.plan.voice }, set: { session.plan.voice = $0 }), label: "Голосовые подсказки")
                            }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 100)
            }
            .scrollIndicators(.hidden)
            SheetButton(title: "Начать занятие", icon: .play, height: 52) { session.start() }
                .padding(.horizontal, 20).padding(.bottom, 20)
        }
    }

    private var totalMinutes: Int { session.plan.steps.map(\.minutes).reduce(0, +) }

    /// Canvas exercise card: a 52 pt head (number, title, tempo · meter, chevron — the preset menu), then «Минут»
    /// (56), «Проверка игры» and «На грифе» (58), each row with its divider.
    private func stepCard(_ index: Int, _ step: PracticeStep) -> some View {
        let presets = app.metronome.state.presets
        return Card {
            HStack(spacing: 10) {
                Menu {
                    Button("Текущие настройки") { update(index) { $0.presetId = nil } }
                    ForEach(presets) { p in Button("\(p.name) · \(Int(p.settings.bpm))") { update(index) { $0.presetId = p.id } } }
                } label: {
                    HStack(spacing: 10) {
                        Text("\(index + 1)").font(Typo.inter(13)).foregroundStyle(Theme.textTertiary)
                        Text(session.title(step)).font(Typo.inter(16, .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(session.tempoText(step)).font(Typo.inter(13)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                        Icon(.chevronDown, size: 14, color: Theme.textTertiary)
                    }
                }
                if session.plan.steps.count > 1 {
                    RoundIconButton(icon: .trash, size: 32, iconSize: 13, label: "Удалить упражнение") {
                        var p = session.plan
                        p.steps.remove(at: index)
                        session.plan = p
                    }
                }
            }
            .padding(.leading, 16).padding(.trailing, 12)
            .frame(height: 52)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1).offset(y: 1) }
            .padding(.bottom, 1)
            PracticeRow(title: "Минут", minHeight: 56) {
                ValueStepper(value: "\(step.minutes)", canDecrement: step.minutes > 1, canIncrement: step.minutes < 60,
                             decrement: { update(index) { $0.minutes -= 1 } }, increment: { update(index) { $0.minutes += 1 } })
            }
            PracticeRow(title: "Проверка игры", subtitle: "темп растёт по результату") {
                ToggleSwitch(isOn: Binding(get: { step.check || step.onNeck }, set: { v in update(index) { $0.check = v; if !v { $0.onNeck = false } } }), label: "Проверка игры")
            }
            PracticeRow(title: "На грифе", subtitle: "ноты позиции проверяются") {
                ToggleSwitch(isOn: Binding(get: { step.onNeck }, set: { v in update(index) { $0.onNeck = v; if v { $0.check = true } } }), label: "На грифе")
            }
        }
    }

    private func update(_ index: Int, _ change: (inout PracticeStep) -> Void) {
        var p = session.plan
        guard p.steps.indices.contains(index) else { return }
        change(&p.steps[index])
        session.plan = p
    }

    // MARK: Running

    private var running: some View {
        VStack(spacing: 0) {
            ring.padding(.top, 46)
            if session.phase == .playing, let step = session.currentStep, step.onNeck {
                // FB-14 inside the session: the position with the current note large and wrong notes red.
                NeckPortrait(courses: app.instrument.courses.count, frets: app.fretboard.visibleFrets, cells: app.fretboard.cells(),
                             leftHanded: app.fretboard.settings.leftHanded,
                             fan: NeckFan(app.instrument.multiscale, courses: app.instrument.courses.count),
                             onTap: { _, _ in }, onLongPress: { _, _, _ in })
                    .frame(height: 110).padding(.horizontal, 22).padding(.top, 12)
            } else {
                beats.padding(.top, 32)
            }
            chips.padding(.top, 16)
            Card {
                PracticeRow(title: "Дальше", minHeight: 52) { Text(nextText).lineLimit(1) }
            }
            .padding(.horizontal, 20).padding(.top, 34)
            Spacer(minLength: 0)
            HStack {
                capsule("Закончить") { session.stop() }
                Spacer()
                Button { session.togglePause() } label: {
                    Icon(session.isPaused ? .play : .pause, size: 28, color: Theme.background)
                        .frame(width: 76, height: 76)
                        .background(Circle().fill(Theme.primaryFill))
                        .shadow(color: .black.opacity(0.6), radius: 9, y: 8)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(session.isPaused ? "Продолжить" : "Пауза")
                Spacer()
                capsule("Дальше") { session.skip() }
            }
            .padding(.horizontal, 20).padding(.bottom, 34)
        }
    }

    /// Canvas ring: 280 pt, radius 120, 8 pt stroke — white 8 % track, ivory remaining part from the top, clockwise.
    private var ring: some View {
        let fraction = session.phaseLength > 0 ? max(0, min(1, session.remaining / session.phaseLength)) : 0
        return ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: 8).frame(width: 240, height: 240)
            Circle().trim(from: 0, to: fraction)
                .stroke(Theme.beat, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 240, height: 240)
            VStack(spacing: 4) {
                Text(Self.clock(session.remaining)).font(Typo.inter(64, .light)).kerning(-1.28).foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                Text(session.phase == .pause ? "пауза из \(Self.clock(session.phaseLength))" : "осталось из \(Self.clock(session.phaseLength))")
                    .font(Typo.inter(13)).foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(width: 280, height: 280)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Осталось \(Self.clock(session.remaining)) из \(Self.clock(session.phaseLength))")
    }

    /// Canvas beats: 34 pt bars, 5 apart, accented 28 high (ivory 38 %), others 18 (white 16 %); the current beat lit.
    private var beats: some View {
        let meter = app.metronome.meter
        return HStack(alignment: .bottom, spacing: 5) {
            ForEach(0..<meter.numerator, id: \.self) { i in
                let accent = i < meter.accents.count ? meter.accents[i] : .normal
                let height: CGFloat = accent == .strong ? 28 : accent == .off ? 6 : 18
                let lit = app.metronome.isPlaying && app.metronome.currentBeat == i
                RoundedRectangle(cornerRadius: 3)
                    .fill(accent == .strong ? Theme.beat.opacity(0.38) : Color.white.opacity(0.16))
                    .overlay(RoundedRectangle(cornerRadius: 3).fill(Theme.beat).shadow(color: Theme.beat.opacity(0.9), radius: 6).opacity(lit ? 1 : 0))
                    .frame(width: 34, height: height)
            }
        }
        .frame(height: 44, alignment: .bottom)
        .accessibilityElement()
        .accessibilityLabel("Доли \(meter.numerator)/\(meter.denominator)")
    }

    private var chips: some View {
        let meter = app.metronome.meter
        return HStack(spacing: 8) {
            Chip(text: "\(Int(app.metronome.displayBPM.rounded())) BPM")
            Chip(text: "\(meter.numerator)/\(meter.denominator)")
            if session.phase == .playing, let step = session.currentStep, step.check || step.onNeck {
                let share = session.demoShare ?? app.playCheck.lastBar?.accurateShare
                HStack(spacing: 6) {
                    Icon(.mic, size: 14, color: Theme.inTune)
                    Text(share.map { "Проверка · \(Int(($0 * 100).rounded())) %" } ?? "Проверка").font(Typo.chip).lineLimit(1)
                }
                .foregroundStyle(Theme.textBody)
                .padding(.horizontal, 13)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.fill))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairlineStrong, lineWidth: 1))
                .fixedSize()
            }
        }
    }

    private var nextText: String {
        let next = session.phase == .pause ? session.currentStep : session.nextStep
        guard let next else { return "конец занятия" }
        return "\(session.title(next)) · \(next.minutes) мин"
    }

    /// Canvas side buttons: 120 × 50 capsules (card fill, hairline), 15 medium.
    private func capsule(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Typo.inter(15, .medium)).foregroundStyle(Theme.textBody)
                .frame(width: 120, height: 50)
                .background(Capsule().fill(Theme.cardFill))
                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Summary (PL-3)

    private var summary: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                let total = session.results.map(\.seconds).reduce(0, +)
                Text("Занятие · \(Self.clock(total))").font(Typo.inter(24, .semibold)).foregroundStyle(Theme.textPrimary)
                Card {
                    ForEach(Array(session.results.enumerated()), id: \.element.id) { i, r in
                        CardRow(title: r.title, subtitle: subtitle(r), showsDivider: i < session.results.count - 1) {
                            Text(Self.clock(r.seconds)).monospacedDigit()
                        }
                    }
                }
                if let weak = weakest {
                    Text("Самое слабое место: \(weak)").font(Typo.inter(14)).foregroundStyle(Theme.textSecondary)
                }
                SheetButton(title: "Готово", height: 52) { session.reset(); dismiss() }.padding(.top, 8)
            }
            .padding(20)
        }
    }

    private func subtitle(_ r: PracticeSessionController.StepResult) -> String? {
        guard let a = r.attempt else { return nil }
        let tempo = a.startBPM == a.endBPM ? "\(Int(a.endBPM))" : "\(Int(a.startBPM))→\(Int(a.endBPM))"
        return "\(Int((a.accurateShare * 100).rounded())) % · темп \(tempo) · разброс \(Int(a.spread.rounded())) мс"
    }

    private var weakest: String? {
        let attempts = session.results.compactMap { r in r.attempt.map { (r.title, $0) } }
        guard let worst = attempts.min(by: { $0.1.accurateShare < $1.1.accurateShare }) else { return nil }
        var text = "«\(worst.0)» — \(Int((worst.1.accurateShare * 100).rounded())) %"
        if let beat = worst.1.weakestBeat, let d = worst.1.weakestBeatDeviation {
            text += ", доля \(beat + 1): " + (d < 0 ? "спешите" : "тянете") + " \(Int(abs(d).rounded())) мс"
        }
        return text
    }

    static func clock(_ s: Double) -> String { String(format: "%d:%02d", max(0, Int(s.rounded())) / 60, max(0, Int(s.rounded())) % 60) }
}

/// Header of the practice pages (canvas `left 20, top 50`, a 44 pt row): a 40 pt round button, 12 apart, the title
/// 17 medium over a 12 pt subtitle (1 apart), an optional trailing button.
struct PracticePageHeader<Trailing: View>: View {
    let icon: AppIcon
    let label: String
    let title: String
    var subtitle: String?
    let action: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            RoundIconButton(icon: icon, iconSize: icon == .close ? 16 : 18, label: label, action: action)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Typo.inter(17, .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).font(Typo.caption).foregroundStyle(Theme.textTertiary).lineLimit(1).monospacedDigit()
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
        .frame(height: 44)
        .padding(.horizontal, 20)
        .padding(.top, 3)
    }
}

extension PracticePageHeader where Trailing == EmptyView {
    init(icon: AppIcon, label: String, title: String, subtitle: String?, action: @escaping () -> Void) {
        self.init(icon: icon, label: label, title: title, subtitle: subtitle, action: action, trailing: { EmptyView() })
    }
}

/// A canvas card row with its CSS box: `min-height` + the 1 pt bottom border (padding 0 16, gap 10, title 15,
/// subtitle 12 two points under it, trailing 14 secondary).
struct PracticeRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var minHeight: CGFloat = 58
    var divider = true
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typo.row).foregroundStyle(Theme.textBody)
                if let subtitle { Text(subtitle).font(Typo.caption).foregroundStyle(Theme.textTertiary) }
            }
            Spacer(minLength: 8)
            trailing().font(Typo.inter(14)).foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: minHeight)
        .padding(.bottom, divider ? 1 : 0)
        .overlay(alignment: .bottom) {
            if divider { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
        }
        .contentShape(Rectangle())
    }
}
