import SwiftUI
import TruverTheory

/// FB-12 «Тренажёр грифа» (corrected canvas «Тренажёр — назови / сыграй / верно / ошибка / итог»).
/// «Назови ноту»: a scrollable neck with fret numbers, the asked cell «?», piano-like keys near the question; a wrong
/// answer says why («Это G, а не C · 8-я струна F♯ + 1 лад = G») and waits for «Дальше». «Сыграй ноту»: the note and
/// the string (highlighted on the neck, the place is to be found), «Слушаю…», «Подсказка» shows the fret; a right
/// answer shows where it was played and goes on in a second. The summary offers «Повторить ошибки».
struct FretTrainerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    private var trainer: FretTrainerController { app.trainer }

    var body: some View {
        ZStack(alignment: .top) {
            if let info = trainer.summaryInfo {
                TrainerSummaryView(info: info, courses: app.instrument.courses.count,
                                   again: { trainer.newSeries() }, repeatMistakes: { trainer.repeatMistakes() }, close: close)
            } else if let q = trainer.question {
                question(q)
            }
            VStack(spacing: 10) {
                PracticePageHeader(icon: .close, label: "Закрыть", title: "Тренажёр грифа", subtitle: progressText, action: close) {
                    if trainer.summaryInfo == nil { optionsMenu }
                }
                if trainer.summaryInfo == nil {
                    Segments(options: [(FretTrainer.Kind.nameNote, "Назови ноту"), (.playNote, "Сыграй ноту")],
                             selection: Binding(get: { trainer.settings.kind }, set: { trainer.settings.kind = $0; trainer.newSeries() }))
                        .padding(.horizontal, 20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ScreenBackground())
        .preferredColorScheme(.dark)
        .onDisappear { trainer.close() }
    }

    private func close() {
        trainer.close()
        dismiss()
    }

    private var progressText: String {
        if trainer.summaryInfo != nil { return "серия завершена" }
        guard let s = trainer.session else { return "" }
        let right = s.answers.filter(\.correct).count
        return "\(min(s.answers.count + 1, s.options.count)) из \(s.options.count) · верно \(right)"
    }

    private var optionsMenu: some View {
        Menu {
            Picker("Струны", selection: binding(\.strings)) {
                Text("Все струны").tag(FretTrainerController.Settings.Strings.all)
                Text("Три нижние").tag(FretTrainerController.Settings.Strings.low)
                Text("Три верхние").tag(FretTrainerController.Settings.Strings.high)
            }
            Picker("Лады", selection: binding(\.frets)) {
                Text("Лады 0–12").tag(FretTrainerController.Settings.Frets.first12)
                Text("Весь гриф").tag(FretTrainerController.Settings.Frets.whole)
                Text("От 12-го лада").tag(FretTrainerController.Settings.Frets.upper)
            }
            Picker("Вопросов", selection: binding(\.count)) {
                ForEach([10, 20, 40], id: \.self) { Text("\($0) вопросов").tag($0) }
            }
            Toggle("Только ноты без знаков", isOn: binding(\.naturalsOnly))
            Toggle("Подсказывать струну", isOn: binding(\.showString))
        } label: {
            TrainerOptionsIcon()
                .frame(width: 40, height: 40)
                .background(RoundButtonFace(size: 40))
        }
        .accessibilityLabel("Настройки тренажёра")
    }

    private func binding<T: Equatable>(_ keyPath: WritableKeyPath<FretTrainerController.Settings, T>) -> Binding<T> {
        Binding(get: { trainer.settings[keyPath: keyPath] }, set: { v in
            guard trainer.settings[keyPath: keyPath] != v else { return }
            trainer.settings[keyPath: keyPath] = v
            if keyPath != \FretTrainerController.Settings.showString { trainer.newSeries() }
        })
    }

    // MARK: Question

    /// Blocks at the canvas tops (screen y − the 47 pt safe area).
    private func at<V: View>(_ y: CGFloat, @ViewBuilder _ content: () -> V) -> some View {
        content().padding(.top, y - 47).frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder private func question(_ q: FretTrainer.Question) -> some View {
        let wrong: Bool = { if case .wrong = trainer.feedback { return true } else { return false } }()
        if trainer.settings.kind == .nameNote {
            at(160) {
                Text("Какая нота?").font(Typo.inter(18, .medium)).foregroundStyle(Theme.textPrimary)
            }
            at(196) { neck(q, height: wrong ? 300 : 340, span: wrong ? 7 : 9) }
            if wrong {
                at(510) {
                    VStack(spacing: 0) {
                        wrongCard(q)
                        keys(q).padding(.top, 12.6)
                        SheetButton(title: "Дальше", height: 48) { trainer.next() }.padding(.top, 20)
                    }
                    .padding(.horizontal, 20)
                }
            } else {
                at(576) { keys(q).padding(.horizontal, 20) }
                if trainer.feedback == .none {
                    at(722) {
                        Button { trainer.skip() } label: { Chip(text: "Пропустить") }.buttonStyle(PressableStyle())
                    }
                }
            }
        } else {
            at(160) {
                VStack(spacing: -2) {
                    Typo.notes(name(q.pitchClass), size: 44, weight: .light).foregroundStyle(Theme.textPrimary)
                    Text(playHint(q)).font(Typo.inter(14)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
            }
            at(252) { neck(q, height: 330, span: 9) }
            switch trainer.feedback {
            case .none:
                at(604) { listeningLine }
                at(700) {
                    HStack(spacing: 8) {
                        Button { trainer.showHint() } label: { Chip(text: "Подсказка") }.buttonStyle(PressableStyle())
                        Button { trainer.skip() } label: { Chip(text: "Пропустить") }.buttonStyle(PressableStyle())
                    }
                }
            case .correct:
                at(600) { rightCard(q).padding(.horizontal, 20) }
            case .wrong:
                at(600) { wrongCard(q).padding(.horizontal, 20) }
                at(748) { SheetButton(title: "Дальше", height: 48) { trainer.next() }.padding(.horizontal, 20) }
            }
        }
    }

    private func stringNumber(_ q: FretTrainer.Question) -> Int { app.instrument.courses.count - q.course }

    private func openName(_ course: Int) -> String {
        guard app.tuning.spelledNotes.indices.contains(course) else { return "" }
        return app.formatter.string(app.tuning.spelledNotes[course].name)
    }

    private func playHint(_ q: FretTrainer.Question) -> String {
        trainer.settings.showString
            ? "сыграйте на \(stringNumber(q))-й струне (\(openName(q.course))) · любая октава"
            : "сыграйте в любом месте грифа · любая октава"
    }

    /// The neck around the asked fret: 9 frets (7 while a wrong answer's card is shown), the cell's dot when it is
    /// asked («?»), answered or hinted, the asked string highlighted in «Сыграй ноту».
    private func neck(_ q: FretTrainer.Question, height: CGFloat, span: Int) -> some View {
        let top = app.instrument.fretCount
        let lower = max(1, min(q.fret - (span - 1) / 2, top - span + 1))
        var dots: [TrainerNeck.Dot] = []
        let label = name(q.pitchClass)
        switch trainer.feedback {
        case .none:
            if trainer.settings.kind == .nameNote { dots.append(.init(course: q.course, fret: q.fret, label: "?", style: .question)) }
            else if trainer.hintShown { dots.append(.init(course: q.course, fret: q.fret, label: label, style: .question)) }
        case .correct:
            dots.append(.init(course: q.course, fret: q.fret, label: label, style: .right(small: trainer.settings.kind == .playNote)))
        case .wrong:
            dots.append(.init(course: q.course, fret: q.fret, label: label, style: .right(small: false)))
        }
        let highlight: TrainerNeck.Highlight? = trainer.settings.kind == .playNote && trainer.settings.showString
            ? .init(course: q.course, right: trainer.feedback == .correct) : nil
        return TrainerNeck(courses: app.instrument.courses.count, fretCount: top, lower: lower, upper: lower + span - 1, height: height,
                           leftHanded: app.fretboard.settings.leftHanded, dots: dots, highlight: highlight)
            .id("\(q.course)-\(q.fret)-\(span)-\(trainer.session?.answers.count ?? 0)")
            .accessibilityElement()
            .accessibilityLabel(trainer.settings.kind == .nameNote ? "Струна \(stringNumber(q)), лад \(q.fret)" : "Струна \(stringNumber(q))")
    }

    // MARK: Feedback

    /// Canvas wrong card: danger 8 % with a 35 % border, «Это G, а не C» 16 semibold, why in 12 under it.
    private func wrongCard(_ q: FretTrainer.Question) -> some View {
        let expected = name(q.pitchClass)
        let heard: Int? = { if case .wrong(_, let h) = trainer.feedback { return h } else { return nil } }()
        let title = heard.map { "Это \(expected), а не \(name($0))" } ?? "Это \(expected)"
        let why = q.fret == 0
            ? "\(stringNumber(q))-я струна \(openName(q.course)) открытая = \(expected)"
            : "\(stringNumber(q))-я струна \(openName(q.course)) + \(q.fret) \(ModeParamsSheet.plural(q.fret, "лад", "лада", "ладов")) = \(expected)"
        return VStack(alignment: .leading, spacing: 3) {
            Typo.notes(title, size: 16, weight: .semibold).foregroundStyle(Theme.textPrimary)
            Typo.notes("\(why) · запомнится в «Повторить ошибки»", size: 12).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 17).padding(.vertical, 13)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.danger.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.danger.opacity(0.35), lineWidth: 1))
    }

    /// Canvas right card: green 10 % with a 35 % border, a check, «Верно · D3», where and how fast, when it goes on.
    private func rightCard(_ q: FretTrainer.Question) -> some View {
        let full = app.formatter.string(SpelledNote(NoteName.simpleSpelling(ofPitchClass: q.pitchClass, preferFlats: false), midi: q.pitch.nearestMIDI))
        let place = q.fret == 0 ? "открытая" : "\(q.fret)-й лад"
        let seconds = String(format: "%.1f", trainer.answerSeconds).replacingOccurrences(of: ".", with: ",")
        return HStack(spacing: 12) {
            Icon(.check, size: 22, lineWidth: 2.4, color: Theme.inTune)
            VStack(alignment: .leading, spacing: 2) {
                Typo.notes("Верно · \(full)", size: 16, weight: .semibold).foregroundStyle(Theme.textPrimary)
                Text("\(stringNumber(q))-я струна, \(place) · \(seconds) с").font(Typo.caption).foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
            Text("дальше через 1 с").font(Typo.caption).foregroundStyle(Theme.textTertiary).fixedSize()
        }
        .padding(.horizontal, 17).padding(.vertical, 13)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.inTune.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.inTune.opacity(0.35), lineWidth: 1))
    }

    /// «Слушаю…» with a green level mark; the note heard so far; the microphone hint when there is no access.
    @ViewBuilder private var listeningLine: some View {
        switch app.tuner.permission {
        case .denied, .restricted:
            Text("Нужен доступ к микрофону — откройте Настройки").font(Typo.inter(15)).foregroundStyle(Theme.sharp)
        default:
            HStack(spacing: 10) {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array([6.0, 12, 18, 10, 5].enumerated()), id: \.offset) { _, h in
                        RoundedRectangle(cornerRadius: 2).fill(Theme.inTune).frame(width: 4, height: h)
                    }
                }
                .frame(height: 18, alignment: .bottom)
                Typo.notes(trainer.heard.map { "Слышу \(name($0))" } ?? "Слушаю…", size: 15).foregroundStyle(Theme.textBody)
            }
        }
    }

    // MARK: Keys

    /// Canvas keys: 7 naturals (62 high, 5 apart) at the bottom of a 128 pt block, 5 sharps (48 × 58) over the gaps
    /// between them; the picked wrong key red, the right one green.
    private func keys(_ q: FretTrainer.Question) -> some View {
        let naturals = [0, 2, 4, 5, 7, 9, 11]
        let sharps: [(pc: Int, boundary: Int)] = [(1, 1), (3, 2), (6, 4), (8, 5), (10, 6)]
        let naturalsOnly = trainer.session?.options.naturalsOnly == true
        return GeometryReader { proxy in
            let w = proxy.size.width
            ZStack(alignment: .topLeading) {
                HStack(spacing: 5) {
                    ForEach(naturals, id: \.self) { pc in
                        key(pc, q) {
                            Typo.notes(name(pc), size: 20, weight: .medium).foregroundStyle(Theme.textPrimary)
                                .frame(maxWidth: .infinity).frame(height: 62)
                        }
                    }
                }
                .offset(y: 66)
                ForEach(sharps, id: \.pc) { s in
                    key(s.pc, q, sharp: true) {
                        VStack(spacing: 1) {
                            Typo.notes(name(s.pc), size: 14, weight: .semibold).foregroundStyle(Theme.textPrimary)
                            Typo.notes(app.formatter.string(NoteName.simpleSpelling(ofPitchClass: s.pc, preferFlats: true)), size: 10)
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .frame(width: 48, height: 58)
                    }
                    .disabled(naturalsOnly).opacity(naturalsOnly ? 0.3 : 1)
                    .offset(x: w * CGFloat(s.boundary) / 7 - 24)
                }
            }
        }
        .frame(height: 128)
    }

    private func key<L: View>(_ pc: Int, _ q: FretTrainer.Question, sharp: Bool = false, @ViewBuilder label: () -> L) -> some View {
        let (fill, border) = keyColors(pc, q, sharp: sharp)
        return Button { trainer.answer(pitchClass: pc) } label: {
            label()
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fill))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(border, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }

    private func keyColors(_ pc: Int, _ q: FretTrainer.Question, sharp: Bool) -> (Color, Color) {
        let plain = (sharp ? Color(hex: 0x0f1012) : Color.white.opacity(0.06), Color.white.opacity(0.1))
        switch trainer.feedback {
        case .correct where pc == q.pitchClass: return (Theme.inTune.opacity(0.18), Theme.inTune.opacity(0.8))
        case .wrong(let expected, let heard):
            if pc == expected { return (Theme.inTune.opacity(0.18), Theme.inTune.opacity(0.8)) }
            if pc == heard { return (Theme.danger.opacity(0.16), Theme.danger.opacity(0.7)) }
            return plain
        default: return plain
        }
    }

    private func name(_ pc: Int) -> String {
        app.formatter.string(NoteName.simpleSpelling(ofPitchClass: pc, preferFlats: false))
    }
}

/// The canvas «Параметры» icon: three lines, a knob on the first (filled with the background).
struct TrainerOptionsIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 24
            var lines = Path()
            for y in [7.0, 12, 17] { lines.move(to: CGPoint(x: 5 * s, y: y * s)); lines.addLine(to: CGPoint(x: 19 * s, y: y * s)) }
            let style = StrokeStyle(lineWidth: 1.6 * s, lineCap: .round)
            ctx.stroke(lines, with: .color(Theme.textBody), style: style)
            let knob = Path(ellipseIn: CGRect(x: 7 * s, y: 5 * s, width: 4 * s, height: 4 * s))
            ctx.fill(knob, with: .color(Theme.background))
            ctx.stroke(knob, with: .color(Theme.textBody), lineWidth: 1.6 * s)
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

/// Series summary (canvas «Тренажёр — итог»): «1 из 20», the mode and frets, three equal cards, the hardest string
/// and the missed notes, «Повторить ошибки», «Ещё серия» and «Готово».
private struct TrainerSummaryView: View {
    @Environment(AppModel.self) private var app
    let info: FretTrainerController.SummaryInfo
    let courses: Int
    let again: () -> Void
    let repeatMistakes: () -> Void
    let close: () -> Void

    private func at<V: View>(_ y: CGFloat, @ViewBuilder _ content: () -> V) -> some View {
        content().padding(.top, y - 47).frame(maxWidth: .infinity, alignment: .top)
    }

    var body: some View {
        let mode = info.kind == .nameNote ? "Назови ноту" : "Сыграй ноту"
        let percent = info.total == 0 ? 0 : Int((Double(info.correct) * 100 / Double(info.total)).rounded())
        let time = String(format: "%.1f", info.averageSeconds).replacingOccurrences(of: ".", with: ",")
        let missed = info.missedPitchClasses.map { app.formatter.string(NoteName.simpleSpelling(ofPitchClass: $0, preferFlats: false)) }
        ZStack(alignment: .top) {
            at(150) {
                VStack(spacing: 4) {
                    Text("\(info.correct) из \(info.total)").font(Typo.inter(64, .semibold)).kerning(-1.28).foregroundStyle(Theme.textPrimary)
                    Text("\(mode) · лады \(info.frets.lowerBound)–\(info.frets.upperBound)").font(Typo.inter(14)).foregroundStyle(Theme.textSecondary)
                }
            }
            at(270) {
                HStack(spacing: 8) {
                    card("Верно", "\(percent) %")
                    card("Среднее время", "\(time) с")
                    card("Лучшая серия", "\(info.bestStreak)")
                }
                .padding(.horizontal, 20)
            }
            if !info.weakCourses.isEmpty || !missed.isEmpty {
                at(386) {
                    Card {
                        if let weak = info.weakCourses.first {
                            PracticeRow(title: "Сложнее всего", minHeight: 52) { Text("струна \(courses - weak)") }
                        }
                        if !missed.isEmpty {
                            PracticeRow(title: "Ошибки на нотах", minHeight: 52) { Typo.notes(missed.joined(separator: " "), size: 14).lineLimit(1) }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            if !missed.isEmpty {
                at(520) {
                    Button(action: repeatMistakes) {
                        Card {
                            PracticeRow(title: "Повторить ошибки", subtitle: "серия только из этих нот") {
                                HStack(spacing: 8) {
                                    Text("\(missed.count) \(ModeParamsSheet.plural(missed.count, "нота", "ноты", "нот"))")
                                    Icon(.chevronRight, size: 16, color: Theme.textTertiary)
                                }
                            }
                        }
                    }
                    .buttonStyle(PressableStyle())
                    .padding(.horizontal, 20)
                }
            }
            at(690) { SheetButton(title: "Ещё серия", height: 52, action: again).padding(.horizontal, 20) }
            at(752) {
                Button(action: close) { Text("Готово").font(Typo.inter(15)).foregroundStyle(Theme.textSecondary) }
                    .buttonStyle(PressableStyle())
            }
        }
    }

    /// Canvas: 96 high (border box), padding 12 × 14, caption 12 (line 1.25, two lines reserved), value 26 light.
    private func card(_ caption: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(caption).font(Typo.caption).foregroundStyle(Theme.textTertiary).lineSpacing(0.47)
                .frame(minHeight: 30, alignment: .topLeading)
            Spacer(minLength: 0)
            Text(value).font(Typo.inter(26, .light)).foregroundStyle(Theme.textPrimary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 15).padding(.vertical, 13)
        .frame(height: 96)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}
