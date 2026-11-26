import SwiftUI
import TruverTheory

/// TU-11 «Проверка мензуры» (6.2.11): pick a string → «Сыграйте открытую струну» → «Сыграйте на 12-м ладу» →
/// «седло от грифа / к грифу, ~N ц, ≈ X мм» → next string. The tuner listens in chromatic mode meanwhile and
/// returns to its mode when the sheet closes.
struct IntonationSheet: View {
    @Environment(AppModel.self) private var app

    private var tuner: TunerController { app.tuner }
    private var courses: Int { app.instrument.courses.count }
    /// Strings go from the low one — the usual setup order.
    private var course: Int { tuner.intonationCourse ?? 0 }

    var body: some View {
        // Canvas «Проверка мензуры» (FixTunerIntonation): the sheet from 356 — 488 pt.
        DesignSheet(title: "Проверка мензуры", height: 488, close: close) {
            VStack(alignment: .leading, spacing: 14) {
                stringPicker
                stepCard
                if !tuner.intonationResults.isEmpty { results }
                Text(note)
                    .font(Typo.inter(13)).foregroundStyle(Theme.textTertiary)
                    // line-height 1.4 on 13 pt: 18.2 pt lines (Inter's own 15.7).
                    .lineSpacing(2.47).padding(.vertical, 1.23)
                    .padding(.horizontal, 4)
            }
        } footer: {
            if case .result = tuner.intonationStep, course + 1 < courses {
                SheetButton(title: "Следующая струна") { tuner.beginIntonation(course: course + 1) }
            } else if case .result = tuner.intonationStep {
                SheetButton(title: "Готово", action: close)
            } else {
                // Canvas: a quiet card-coloured button, 50 pt.
                Button { tuner.repeatIntonationStep() } label: {
                    Text("Начать заново").font(Typo.inter(15, .medium)).foregroundStyle(Theme.textBody)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Capsule(style: .circular).fill(Theme.cardFill))
                        .overlay(Capsule(style: .circular).strokeBorder(Theme.hairline, lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
            }
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-intonationDemo") {
                tuner.injectIntonationDemo(hint: "Слышу F♯3")
                return
            }
            #endif
            if tuner.intonationCourse == nil { tuner.beginIntonation(course: 0) }
            if !tuner.isListening { Task { await tuner.start(confirmedGap: true) } }
        }
    }

    private var note: String {
        switch tuner.intonationStep {
        case .open: return "Дальше — 12-й лад обычным нажатием. Седло двигают на ослабленной струне."
        case .twelfth: return "Нажимайте обычно, не флажолетом. Седло двигают на ослабленной струне."
        case .result: return "Седло двигают на ослабленной струне, потом снова настраивают и проверяют."
        }
    }

    private func close() {
        tuner.endIntonation()
        app.sheet = nil
    }

    /// Canvas: all strings in one row (gap 6), 48 pt keys, radius 12, 15 pt — semibold ivory with a ring when chosen.
    private var stringPicker: some View {
        HStack(spacing: 6) {
            ForEach(0..<courses, id: \.self) { c in
                let selected = c == course
                Button { tuner.beginIntonation(course: c) } label: {
                    Typo.notes(app.stringName(StringRef(course: c)), size: 15, weight: selected ? .semibold : .medium)
                        .foregroundStyle(selected ? Theme.textPrimary : (tuner.intonationResults[c] == nil ? Theme.textMuted : resultColor(c)))
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(selected ? 0.09 : 0.04)))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? Theme.selectedBorder : Theme.hairline, lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Струна \(courses - c), \(app.stringName(StringRef(course: c)))")
                .accessibilityValue(tuner.intonationResults[c].map { signed($0) + " центов" } ?? "")
            }
        }
    }

    private func resultColor(_ c: Int) -> Color {
        guard let cents = tuner.intonationResults[c] else { return Theme.textTertiary }
        return Intonation.verdict(cents: cents) == .ok ? Theme.inTune : (cents > 0 ? Theme.sharp : Theme.flat)
    }

    /// Canvas card: padding 14 / 16, rows 10 apart — the step, a 4 pt progress line, the hint 13 pt.
    @ViewBuilder private var stepCard: some View {
        let name = app.stringName(StringRef(course: course))
        let number = courses - course
        VStack(alignment: .leading, spacing: 10) {
            switch tuner.intonationStep {
            case .open:
                step(number: 1, title: "Сыграйте открытую струну", detail: "шаг 1 из 3 · струна \(number) · \(name)")
            case .twelfth:
                step(number: 2, title: "Сыграйте на 12-м ладу", detail: "шаг 2 из 3 · струна \(number) · октава \(name)")
            case .result(let cents):
                result(cents)
            }
            if case .result = tuner.intonationStep {} else {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.1))
                        Capsule().fill(Theme.beat).frame(width: geo.size.width * tuner.intonationProgress)
                    }
                }
                .frame(height: 4)
                Typo.notes(tuner.intonationHint.map { "\($0) — нужна " + (tuner.intonationStep == .open ? "открытая \(number)-я струна" : "октава на 12-м ладу") }
                           ?? (tuner.intonationProgress > 0 ? "Держите ноту…" : "Слушаю…"), size: 13)
                    .foregroundStyle(tuner.intonationHint == nil ? Theme.textTertiary : Theme.sharp)
            }
        }
        .padding(.horizontal, 17).padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    /// A 28 pt ivory disc with the step number (14 semibold), title 16 medium, detail 12 tertiary 2 pt under it.
    private func step(number: Int, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Text("\(number)").font(Typo.inter(14, .semibold)).foregroundStyle(Theme.background)
                .frame(width: 28, height: 28).background(Circle().fill(Theme.beat))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typo.inter(16, .medium)).foregroundStyle(Theme.textPrimary)
                Typo.notes(detail, size: 12).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    @ViewBuilder private func result(_ cents: Double) -> some View {
        let verdict = Intonation.verdict(cents: cents)
        let mm = abs(Intonation.saddleShift(cents: cents, scaleLength: scaleLength))
        let color = verdict == .ok ? Theme.inTune : (cents > 0 ? Theme.sharp : Theme.flat)
        VStack(alignment: .leading, spacing: 6) {
            Text(signed(cents) + " ц").font(Typo.inter(40, .semibold)).foregroundStyle(color).monospacedDigit()
            switch verdict {
            case .ok:
                Text("В порядке — 12-й лад совпадает с октавой").font(Typo.inter(17, .medium)).foregroundStyle(Theme.textPrimary)
            case .awayFromNeck:
                Text("Седло от грифа · ≈ \(millimetres(mm))").font(Typo.inter(17, .medium)).foregroundStyle(Theme.textPrimary)
                Text("12-й лад выше октавы: струна коротковата").font(Typo.caption).foregroundStyle(Theme.textSecondary)
            case .towardsNeck:
                Text("Седло к грифу · ≈ \(millimetres(mm))").font(Typo.inter(17, .medium)).foregroundStyle(Theme.textPrimary)
                Text("12-й лад ниже октавы: струна длинновата").font(Typo.caption).foregroundStyle(Theme.textSecondary)
            }
            Button { tuner.repeatIntonationStep() } label: { Chip(text: "Измерить ещё раз", style: .muted) }
                .buttonStyle(PressableStyle())
                .padding(.top, 4)
        }
        .accessibilityElement(children: .combine)
    }

    private var results: some View {
        let done = tuner.intonationResults.keys.sorted()
        return VStack(spacing: 0) {
            SectionCaption(text: "Измерено")
            Card {
                ForEach(Array(done.enumerated()), id: \.element) { i, c in
                    let cents = tuner.intonationResults[c] ?? 0
                    let verdict = Intonation.verdict(cents: cents)
                    let mm = abs(Intonation.saddleShift(cents: cents, scaleLength: scaleLength(for: c)))
                    CardRow(title: "Струна \(courses - c) · \(app.stringName(StringRef(course: c)))",
                            subtitle: verdict == .ok ? "в порядке" : (verdict == .awayFromNeck ? "от грифа" : "к грифу") + " ≈ \(millimetres(mm))",
                            showsDivider: i < done.count - 1) {
                        Text(signed(cents) + " ц").foregroundStyle(resultColor(c)).monospacedDigit()
                    }
                }
            }
        }
    }

    private var scaleLength: Double { scaleLength(for: course) }

    /// The string's own scale (fanned frets — PR-7), else the instrument's.
    private func scaleLength(for c: Int) -> Double {
        let i = app.instrument
        if let m = i.multiscale { return m.scaleLength(course: c, courses: i.courses.count) }
        return i.courses[safe: c]?.strings.first?.scaleLength ?? Double(InstrumentSheet.defaultScale(i))
    }

    private func millimetres(_ mm: Double) -> String {
        String(format: "%.1f мм", mm).replacingOccurrences(of: ".", with: ",")
    }

    private func signed(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        let text = String(format: "%.1f", abs(r)).replacingOccurrences(of: ".", with: ",")
        return (r > 0 ? "+" : r < 0 ? "−" : "") + text
    }
}
