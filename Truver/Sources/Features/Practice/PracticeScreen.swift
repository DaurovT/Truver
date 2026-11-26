import SwiftData
import SwiftUI

/// «Занятия» (corrected canvas «Занятия — графики» / «Занятия — пусто», PL-0, PL-4): the session and trainer entries,
/// the week and the streak, the play check's ceiling and spread with the ceiling chart (the numbers come from the same
/// data as the chart), the journal by days below. No tuning pill on this tab.
struct PracticeScreen: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \PracticeEntry.start, order: .reverse) private var entries: [PracticeEntry]

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Занятия")
            VStack(spacing: 10) {
                entryCard(icon: .timer, title: "Занятие", subtitle: sessionSubtitle) { app.showSession = true }
                entryCard(icon: .fretboard, title: "Тренажёр грифа", subtitle: "Назови или сыграй ноту") { app.showTrainer = true }
                    .coachAnchor(CoachCatalog.Anchor.trainer)
            }
            .padding(.horizontal, 20).padding(.top, 14)
            if isEmpty {
                empty
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        HStack(spacing: 10) {
                            PracticeStat(caption: "За неделю", value: Self.duration(weekSeconds))
                            PracticeStat(caption: "Дней подряд", value: "\(streak)")
                        }
                        if !history.isEmpty {
                            VStack(spacing: 0) {
                                SectionCaption(text: "Проверка игры")
                                PlayCheckCharts(history: history)
                            }
                            .padding(.top, 18)
                        }
                        VStack(spacing: 16) {
                            ForEach(days, id: \.day) { group in
                                CardGroup(title: "\(Self.dayTitle(group.day)) · \(Self.duration(group.items.reduce(0) { $0 + $1.seconds }))") {
                                    // One row per instrument and tuning in a day, the metronome by preset under it.
                                    let sessions = merged(group.items)
                                    ForEach(Array(sessions.enumerated()), id: \.offset) { index, session in
                                        row(session, last: index == sessions.count - 1)
                                    }
                                }
                            }
                            Text("Считаются занятия от 30 секунд: время, пока играет метроном или тюнер слышит инструмент")
                                .font(Typo.caption).foregroundStyle(Theme.textTertiary).multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.top, 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    /// Play-check history: the controller's, or the screenshot demo (`-practiceDemo`, `-practiceEmpty`).
    private var history: [PlayAttempt] { app.practice.demoHistory ?? app.playCheck.history }
    private var isEmpty: Bool { days.isEmpty && history.isEmpty }

    private var sessionSubtitle: String {
        if isEmpty { return "составьте план из упражнений" }
        let plan = app.session.plan
        let minutes = plan.steps.map(\.minutes).reduce(0, +)
        return "\(plan.steps.count) \(ModeParamsSheet.plural(plan.steps.count, "упражнение", "упражнения", "упражнений")) · \(minutes) мин"
    }

    /// Canvas entry card: 64 high + the 1 pt border outside (CSS content box), radius 16, icon in a 40 pt circle (white 6 %), title 15 medium, subtitle 12.
    private func entryCard(icon: AppIcon, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Icon(icon, size: 20, color: Theme.textBody)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.06)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Typo.inter(15, .medium)).foregroundStyle(Theme.textPrimary)
                    Text(subtitle).font(Typo.caption).foregroundStyle(Theme.textTertiary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Icon(.chevronRight, size: 16, color: Theme.textTertiary)
            }
            .padding(.horizontal, 15)
            .frame(height: 66)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cardFill))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }

    /// Canvas «Здесь будет ваш прогресс»: 80 pt under the cards, a 64 pt ring (+ border) with the practice icon, the button opens
    /// the session plan.
    private var empty: some View {
        VStack(spacing: 10) {
            Icon(.practice, size: 26, color: Theme.textSecondary)
                .frame(width: 66, height: 66)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            Text("Здесь будет ваш прогресс").font(Typo.inter(18, .semibold)).foregroundStyle(Theme.textPrimary)
            Text("Минуты занятий, дни подряд и потолок темпа появятся после первого занятия с метрономом")
                .font(Typo.inter(13)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                .lineSpacing(3.1)
                .padding(.vertical, 1.55)     // CSS line-height 1.45: half the extra leading above and below
                .frame(maxWidth: 280)
            PrimaryButton(title: "Начать первое занятие", height: 48, maxWidth: nil) { app.showSession = true }
                .fixedSize()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// A day's practice on one instrument and tuning.
    struct Session {
        var title: String
        var first: Date
        var last: Date
        var seconds: Double
        var tuned: Bool
        var metronome: [(name: String, minBPM: Double, maxBPM: Double)]
    }

    private func merged(_ items: [PracticeEntry]) -> [Session] {
        var order: [String] = []
        var byKey: [String: Session] = [:]
        for e in items.sorted(by: { $0.start < $1.start }) {
            let title = "\(AppModel.shortInstrumentName(e.instrumentName)) · \(e.tuningName)"
            let end = e.start.addingTimeInterval(e.seconds)
            var s = byKey[title] ?? Session(title: title, first: e.start, last: end, seconds: 0, tuned: false, metronome: [])
            s.first = min(s.first, e.start)
            s.last = max(s.last, end)
            s.seconds += e.seconds
            s.tuned = s.tuned || e.tuned
            if e.usedMetronome {
                let name = e.presetName
                let low = e.minBPM > 0 ? e.minBPM : e.lastBPM
                if let i = s.metronome.firstIndex(where: { $0.name == name }) {
                    s.metronome[i].minBPM = min(s.metronome[i].minBPM, low)
                    s.metronome[i].maxBPM = max(s.metronome[i].maxBPM, e.lastBPM)
                } else {
                    s.metronome.append((name, low, e.lastBPM))
                }
            }
            if byKey[title] == nil { order.append(title) }
            byKey[title] = s
        }
        return order.compactMap { byKey[$0] }.reversed()
    }

    @ViewBuilder private func row(_ session: Session, last: Bool) -> some View {
        let time = "\(session.first.formatted(date: .omitted, time: .shortened))–\(session.last.formatted(date: .omitted, time: .shortened))"
        CardRow(title: session.title,
                subtitle: session.tuned ? "\(time) · инструмент настроен ✓" : time,
                showsDivider: !last || !session.metronome.isEmpty) {
            Text(Self.duration(session.seconds))
        }
        ForEach(Array(session.metronome.enumerated()), id: \.offset) { index, m in
            let tempo = Int(m.minBPM) == Int(m.maxBPM) ? "\(Int(m.maxBPM))" : "\(Int(m.minBPM))–\(Int(m.maxBPM))"
            Button {
                // Canvas «Пресет метронома · тап — открыть»: the preset if it still exists, else just the tempo.
                if let preset = app.metronome.state.presets.first(where: { $0.name == m.name }), !m.name.isEmpty {
                    app.metronome.load(preset)
                } else {
                    app.metronome.bpm = m.maxBPM
                }
                app.settings.lastTab = .metronome
            } label: {
                CardRow(title: m.name.isEmpty ? "Метроном" : m.name,
                        subtitle: m.name.isEmpty ? "тап — открыть с этим темпом" : "Пресет метронома · тап — открыть",
                        showsDivider: !last || index < session.metronome.count - 1) {
                    HStack(spacing: 8) {
                        Text(tempo)
                        Icon(.chevronRight, size: 16, color: Theme.textTertiary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Data

    private var meaningful: [PracticeEntry] { entries.filter { $0.seconds >= 30 } }

    private var days: [(day: Date, items: [PracticeEntry])] {
        Dictionary(grouping: meaningful) { Calendar.current.startOfDay(for: $0.start) }
            .map { (day: $0.key, items: $0.value) }
            .sorted { $0.day > $1.day }
    }

    private var weekSeconds: Double {
        let from = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .distantPast
        return meaningful.filter { $0.start >= from }.reduce(0) { $0 + $1.seconds }
    }

    private var streak: Int {
        let set = Set(days.map(\.day))
        var day = Calendar.current.startOfDay(for: .now)
        if !set.contains(day) { day = Calendar.current.date(byAdding: .day, value: -1, to: day)! }
        var count = 0
        while set.contains(day) {
            count += 1
            day = Calendar.current.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    static func dayTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Сегодня" }
        if Calendar.current.isDateInYesterday(day) { return "Вчера" }
        return day.formatted(.dateTime.day().month(.wide).weekday(.wide))
    }

    /// «5 мин», «2 ч 10 мин» (canvas).
    static func duration(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60) ч \(minutes % 60) мин" : "\(max(1, minutes)) мин"
    }
}

/// Canvas stat card of the practice tab: padding 12 × 14, caption 12, value 26 light 2 pt below.
struct PracticeStat: View {
    let caption: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption).font(Typo.caption).foregroundStyle(Theme.textTertiary)
            Text(value).font(Typo.inter(26, .light)).foregroundStyle(Theme.textPrimary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 15).padding(.vertical, 13)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}
