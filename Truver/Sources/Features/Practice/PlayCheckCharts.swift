import SwiftUI

/// PL-4 (corrected canvas «Занятия — графики»): the ceiling and the spread of the last day as numbers, the ceiling
/// over days (weeks once there is a month of data) as a line with three gridlines, and the heat map of the beats
/// below — where you rush, where you drag. No badges or points (PL-6).
struct PlayCheckCharts: View {
    let history: [PlayAttempt]

    struct Point: Identifiable {
        var date: Date
        var ceiling: Double
        var spread: Double
        var id: Date { date }
    }

    private var byWeeks: Bool {
        guard let first = history.first?.date, let last = history.last?.date else { return false }
        return last.timeIntervalSince(first) > 21 * 86_400
    }

    private var points: [Point] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: history) { a -> Date in
            byWeeks ? (calendar.dateInterval(of: .weekOfYear, for: a.date)?.start ?? a.date) : calendar.startOfDay(for: a.date)
        }
        return groups.keys.sorted().map { day in
            let items = groups[day]!
            let ceiling = items.map { $0.ceiling ?? $0.endBPM }.max() ?? 0
            let spread = items.map(\.spread).reduce(0, +) / Double(items.count)
            return Point(date: day, ceiling: ceiling, spread: spread)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            let pts = points
            if let last = pts.last {
                HStack(spacing: 10) {
                    PracticeStat(caption: "Потолок темпа", value: "\(Int(last.ceiling.rounded()))")
                    PracticeStat(caption: "Разброс", value: "\(Int(last.spread.rounded())) мс")
                }
            }
            if pts.count < 2 {
                Text("График появится со второго дня занятий с проверкой игры").font(Typo.caption).foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4).padding(.top, 12)
            } else {
                CeilingChart(points: pts, byWeeks: byWeeks).padding(.top, 18.5)
            }
            heatMap.padding(.top, 20)
        }
    }

    /// Mean deviation per beat over the last 20 attempts: orange — early (rushing), blue — late (dragging).
    private var heatMap: some View {
        let recent = history.suffix(20)
        var sums: [Int: (Double, Int)] = [:]
        for a in recent { for (beat, d) in a.perBeat { let s = sums[beat] ?? (0, 0); sums[beat] = (s.0 + d, s.1 + 1) } }
        let beats = sums.keys.sorted()
        return VStack(alignment: .leading, spacing: 8) {
            Text("Доли: где спешите и где тянете · последние \(recent.count)").font(Typo.caption).foregroundStyle(Theme.textTertiary)
            if beats.isEmpty {
                Text("Появится после попыток с проверкой игры").font(Typo.caption).foregroundStyle(Theme.textTertiary)
            } else {
                HStack(spacing: 4) {
                    ForEach(beats, id: \.self) { beat in
                        let v = sums[beat].map { $0.0 / Double($0.1) } ?? 0
                        let k = min(1, abs(v) / 25)
                        VStack(spacing: 2) {
                            Text("\(v < 0 ? "−" : "+")\(Int(abs(v).rounded()))").font(Typo.inter(12, .semibold)).foregroundStyle(Theme.textPrimary).monospacedDigit()
                            Text("\(beat + 1)").font(Typo.inter(10)).foregroundStyle(Theme.textTertiary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 8).fill((v < 0 ? Theme.sharp : Theme.flat).opacity(0.12 + 0.6 * k)))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Доля \(beat + 1): \(v < 0 ? "спешите" : "тянете") \(Int(abs(v).rounded())) мс")
                    }
                }
                Text("мс от доли: «−» — раньше, «+» — позже").font(Typo.inter(11)).foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 15).padding(.vertical, 13)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

/// The canvas chart card: caption, a 310 × 140 plot (the canvas SVG's `viewBox="-4 -6 330 150"` scaled by 0.9333:
/// 300 units of plot, three gridlines 60 units apart labelled on the right), first date and «сегодня» under it.
struct CeilingChart: View {
    let points: [PlayCheckCharts.Point]
    let byWeeks: Bool

    /// Three gridlines: the smallest step (5, 10, 15, 20, 25, 50…) whose range from a multiple of it covers the data.
    static func grid(_ values: [Double]) -> (low: Double, step: Double) {
        let lo = values.min() ?? 0, hi = values.max() ?? 0
        for step in [5.0, 10, 15, 20, 25, 30, 40, 50, 75, 100] {
            let low = (lo / step).rounded(.down) * step
            if low + 2 * step >= hi { return (low, step) }
        }
        return ((lo / 100).rounded(.down) * 100, max(100, ((hi - lo) / 200).rounded(.up) * 100))
    }

    private var title: String {
        let n = points.count
        return byWeeks
            ? "Потолок темпа, BPM · \(n) \(ModeParamsSheet.plural(n, "неделя", "недели", "недель"))"
            : "Потолок темпа, BPM · \(n) \(ModeParamsSheet.plural(n, "день", "дня", "дней"))"
    }

    private var firstLabel: String {
        guard let first = points.first?.date else { return "" }
        return first.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "ru_RU")))
    }

    private var lastLabel: String {
        guard let last = points.last?.date else { return "" }
        if Calendar.current.isDateInToday(last) || (byWeeks && Date().timeIntervalSince(last) < 7 * 86_400) { return "сегодня" }
        return last.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "ru_RU")))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(Typo.caption).foregroundStyle(Theme.textTertiary)
            plot.frame(width: 310, height: 140).padding(.top, 10)
            HStack {
                Text(firstLabel)
                Spacer()
                Text(lastLabel)
            }
            .font(Typo.inter(11)).foregroundStyle(Theme.textTertiary)
            // margin-top 2 + the descender room the inline SVG leaves in its line box (≈ 3.7).
            .padding(.top, 5.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 15).padding(.top, 13).padding(.bottom, 14.3)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Потолок темпа: от \(Int(points.first?.ceiling ?? 0)) до \(Int(points.last?.ceiling ?? 0))")
    }

    private var plot: some View {
        let (low, step) = Self.grid(points.map(\.ceiling))
        let k: CGFloat = 140.0 / 150.0
        func X(_ x: CGFloat) -> CGFloat { 1 + (x + 4) * k }
        func Y(_ y: CGFloat) -> CGFloat { (y + 6) * k }
        let labelFont = Typo.inter(10 * k)
        return Canvas { ctx, _ in
            for i in 0..<3 {
                let y = CGFloat(i) * 60
                var line = Path()
                line.move(to: CGPoint(x: X(0), y: Y(y)))
                line.addLine(to: CGPoint(x: X(300), y: Y(y)))
                ctx.stroke(line, with: .color(Color.white.opacity(0.07)), lineWidth: k)
                let value = low + step * Double(2 - i)
                let text = ctx.resolve(Text("\(Int(value))").font(labelFont).foregroundColor(Theme.textTertiary))
                // SVG text sits on its baseline; the resolved text's bottom is the descender under it.
                ctx.draw(text, at: CGPoint(x: X(306), y: Y(y + 3) + 10 * k * 0.2421875), anchor: .bottomLeading)
            }
            let n = points.count
            let pts = points.enumerated().map { i, p in
                CGPoint(x: X(n > 1 ? CGFloat(i) * 300 / CGFloat(n - 1) : 0),
                        y: Y(CGFloat((low + 2 * step - p.ceiling) / step * 60)))
            }
            var path = Path()
            path.addLines(pts)
            ctx.stroke(path, with: .color(Theme.textPrimary), style: StrokeStyle(lineWidth: 2 * k, lineJoin: .miter))
            for p in pts {
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2.5 * k, y: p.y - 2.5 * k, width: 5 * k, height: 5 * k)), with: .color(Theme.textPrimary))
            }
        }
    }
}
