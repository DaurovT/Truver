import SwiftUI
import TruverDSP

/// A rhythmic figure drawn in notation (user: «как в Soundbrenner»): note heads with stems up, beams by value
/// (eighth — one, sixteenth — two, thirty-second — three), partial beams for mixed figures (8-16-16, 16-8-16),
/// dots, the tuplet number over the beam, eighth rests where the figure starts after the beat.
struct RhythmGlyph: View {
    let rhythm: BeatRhythm
    var color: Color = Theme.textPrimary
    /// The beat's note value: in 6/8 or 7/8 a beat is an eighth, so one click per beat is drawn as an eighth.
    var denominator: Int = 4

    var body: some View {
        Canvas { context, size in
            draw(&context, size: size)
        }
        .accessibilityLabel(BeatRhythms.spokenName(rhythm))
    }

    /// A note of the figure in notation: length in quarter notes of the plain value it stands for (tuplets are
    /// written as the value they replace: triplet eighths as eighths under «3»).
    private struct Note { var value: Double }

    private var nominalStepsPerQuarter: Double {
        pow(2, floor(log2(max(0.25, rhythm.stepsPerBeat)))) * Double(max(1, denominator)) / 4
    }

    private func beams(_ value: Double) -> Int {
        switch value {
        case ..<0.13: return 3
        case ..<0.26: return 2
        case ..<0.38: return 2      // dotted sixteenth
        case ..<0.76: return 1      // eighth, dotted eighth
        default: return 0
        }
    }

    private func dotted(_ value: Double) -> Bool {
        [0.375, 0.75, 1.5, 3].contains { abs($0 - value) < 1e-6 }
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        let h = size.height
        let headW = min(8, h * 0.3), headH = headW * 0.72
        let stemTop = h * 0.12 + (rhythm.tuplet != nil ? h * 0.12 : 0)
        let headY = h - headH / 2 - 1
        let shading = GraphicsContext.Shading.color(color)

        func head(at x: CGFloat, hollow: Bool) {
            let t = CGAffineTransform(translationX: x, y: headY).rotated(by: -0.35)
            let path = Path(ellipseIn: CGRect(x: -headW / 2, y: -headH / 2, width: headW, height: headH)).applying(t)
            if hollow { context.stroke(path, with: shading, lineWidth: 1.3) } else { context.fill(path, with: shading) }
        }
        let stemX: (CGFloat) -> CGFloat = { $0 + headW / 2 - 0.6 }
        func stem(at x: CGFloat) {
            var p = Path()
            p.move(to: CGPoint(x: stemX(x), y: headY - 1))
            p.addLine(to: CGPoint(x: stemX(x), y: stemTop))
            context.stroke(p, with: shading, lineWidth: 1.2)
        }

        // Values of the notes: steps / nominal steps per quarter (whole bar figures count in quarters of 4/4).
        let nominal = nominalStepsPerQuarter
        let values = rhythm.durations.map { Double($0) / nominal }
        let leadRest = rhythm.onsets.first.map { $0 > 0 } ?? true
        let notes = values.count
        let slots = notes + (leadRest ? 1 : 0)
        let pad = headW / 2 + 2
        let step = slots > 1 ? (size.width - 2 * pad - headW / 2) / CGFloat(slots - 1) : 0
        let xs = slots == 1 ? [size.width / 2 - headW / 2] : (0..<slots).map { pad + CGFloat($0) * step }
        if leadRest, let x = xs.first {
            // The rest drawn by its length (it was always an eighth rest): 16th, 8th, quarter, half.
            let restValue = Double(rhythm.onsets.first ?? rhythm.grid) / nominal
            var r = Path()
            switch restValue {
            case ..<0.3:          // sixteenth: a stroke with two flags
                r.move(to: CGPoint(x: x + 3, y: h * 0.34)); r.addLine(to: CGPoint(x: x - 1, y: h * 0.86))
                context.stroke(r, with: shading, lineWidth: 1.2)
                for dy in [0.30, 0.48] {
                    context.fill(Path(ellipseIn: CGRect(x: x - 2, y: h * dy, width: 3, height: 3)), with: shading)
                }
            case ..<0.8:          // eighth
                r.move(to: CGPoint(x: x + 3, y: h * 0.38)); r.addLine(to: CGPoint(x: x - 1, y: h * 0.82))
                context.stroke(r, with: shading, lineWidth: 1.2)
                context.fill(Path(ellipseIn: CGRect(x: x - 1, y: h * 0.32, width: 3, height: 3)), with: shading)
            case ..<1.6:          // quarter: the zigzag
                r.move(to: CGPoint(x: x - 1, y: h * 0.30)); r.addLine(to: CGPoint(x: x + 3, y: h * 0.46))
                r.addLine(to: CGPoint(x: x - 1, y: h * 0.60)); r.addLine(to: CGPoint(x: x + 3, y: h * 0.74))
                r.addQuadCurve(to: CGPoint(x: x + 1, y: h * 0.90), control: CGPoint(x: x - 3, y: h * 0.80))
                context.stroke(r, with: shading, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            default:              // half: a block on the line
                context.fill(Path(CGRect(x: x - 3, y: h * 0.58, width: 7, height: 3)), with: shading)
                context.fill(Path(CGRect(x: x - 5, y: h * 0.58 + 3, width: 11, height: 1)), with: shading)
            }
        }
        let noteXs = Array(xs.suffix(notes))
        let beamCounts = values.map(beams)
        for (i, x) in noteXs.enumerated() {
            let v = values[i]
            head(at: x, hollow: v >= 2)
            if v < 4 { stem(at: x) }
            if dotted(v) {
                context.fill(Path(ellipseIn: CGRect(x: x + headW / 2 + 1.5, y: headY - 1.5, width: 2.4, height: 2.4)), with: shading)
            }
        }
        let beamH: CGFloat = max(1.8, h * 0.07)
        let gap = beamH + 1.6
        // Beam groups: runs of neighbouring notes that have beams; a lone beamed note gets flags.
        var i = 0
        while i < notes {
            guard beamCounts[i] > 0 else { i += 1; continue }
            var j = i
            while j + 1 < notes && beamCounts[j + 1] > 0 { j += 1 }
            if i == j {
                let x = noteXs[i]
                for b in 0..<beamCounts[i] {
                    var f = Path()
                    let y = stemTop + CGFloat(b) * gap
                    f.move(to: CGPoint(x: stemX(x), y: y))
                    f.addQuadCurve(to: CGPoint(x: stemX(x) + 5, y: y + 7), control: CGPoint(x: stemX(x) + 5, y: y + 2))
                    context.stroke(f, with: shading, lineWidth: 1.3)
                }
            } else {
                context.fill(Path(CGRect(x: stemX(noteXs[i]) - 0.6, y: stemTop, width: stemX(noteXs[j]) - stemX(noteXs[i]) + 1.2, height: beamH)), with: shading)
                let deepest = beamCounts[i...j].max() ?? 1
                if deepest >= 2 {
                    for level in 1..<deepest {
                        let y = stemTop + CGFloat(level) * gap
                        for k in i...j where beamCounts[k] > level {
                            let left = k > i && beamCounts[k - 1] > level
                            let right = k < j && beamCounts[k + 1] > level
                            if right {
                                context.fill(Path(CGRect(x: stemX(noteXs[k]) - 0.6, y: y, width: stemX(noteXs[k + 1]) - stemX(noteXs[k]) + 1.2, height: beamH)), with: shading)
                            } else if !left {
                                let w = min(6, step * 0.45)
                                let x0 = k < j ? stemX(noteXs[k]) - 0.6 : stemX(noteXs[k]) - w + 0.6
                                context.fill(Path(CGRect(x: x0, y: y, width: w, height: beamH)), with: shading)
                            }
                        }
                    }
                }
            }
            i = j + 1
        }
        if let label = rhythm.tupletLabel {
            let y = stemTop - h * 0.14
            let text = Text(label).font(.system(size: max(8, h * 0.28), weight: .semibold)).foregroundColor(color)
            context.draw(text, at: CGPoint(x: size.width / 2, y: y))
            // Unbeamed tuplets (quarters, halves) get a bracket, so the number does not hang in the air.
            if beamCounts.allSatisfy({ $0 == 0 }), let first = noteXs.first, let last = noteXs.last, last > first {
                let w = CGFloat(label.count) * h * 0.2 + 6
                var br = Path()
                br.move(to: CGPoint(x: first, y: y + 4)); br.addLine(to: CGPoint(x: first, y: y))
                br.addLine(to: CGPoint(x: size.width / 2 - w / 2, y: y))
                br.move(to: CGPoint(x: size.width / 2 + w / 2, y: y)); br.addLine(to: CGPoint(x: stemX(last), y: y))
                br.addLine(to: CGPoint(x: stemX(last), y: y + 4))
                context.stroke(br, with: shading, lineWidth: 0.9)
            }
        }
    }
}

/// The note value button on the metronome screen: the current figure in notation; opens the grid. With «Лесенка
/// делений» it shows the ladder's current step (PRD 6.2.6: the chip shows the step).
struct RhythmChip: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let metronome = app.metronome
        let shown = metronome.ladderRhythm ?? metronome.currentRhythm
        // Canvas: a 36 pt chip with «♫» 18 pt; a chosen figure is drawn in notation instead.
        Button { app.sheet = .metroRhythm } label: {
            Group {
                if shown.span == 1 && shown.isPlain && shown.grid == 1 {
                    Text("♫").font(.system(size: 18)).foregroundStyle(Theme.textBody)
                } else {
                    RhythmGlyph(rhythm: shown, denominator: metronome.meter.denominator)
                        .frame(width: glyphWidth(shown), height: 22)
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.fill))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Ритм: \(BeatRhythms.spokenName(shown))")
        .accessibilityHint("Открывает выбор ритма")
    }

    private func glyphWidth(_ r: BeatRhythm) -> CGFloat {
        r.onsets.count <= 1 && r.onsets.first == 0 ? 14 : CGFloat(min(9, r.onsets.count + 1)) * 7 + 6
    }
}

/// «Ритм»: all figures by section with jump chips and «Недавние», one tap chooses and closes (Soundbrenner-style).
/// With `beat` the choice applies to that beat only («Как у всех долей» clears it).
struct RhythmSheet: View {
    @Environment(AppModel.self) private var app
    var beat: Int?

    private static let recentKey = "rhythm.recent"
    private var recent: [BeatRhythm] {
        (UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? []).compactMap(BeatRhythms.rhythm(id:))
            .filter { beat == nil || $0.span == 1 }
    }

    private func remember(_ r: BeatRhythm) {
        var ids = UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? []
        ids.removeAll { $0 == r.id }
        ids.insert(r.id, at: 0)
        UserDefaults.standard.set(Array(ids.prefix(8)), forKey: Self.recentKey)
    }

    var body: some View {
        let metronome = app.metronome
        let ladder = metronome.state.modes.subdivision == .ladder
        // Nothing is marked while the ladder leads (the chip shows its step).
        let current: BeatRhythm? = ladder ? nil : (beat.map { metronome.meter.beatRhythms?[safe: $0] ?? nil } ?? metronome.currentRhythm)
        let groups = BeatRhythmGroup.allCases.filter { g in BeatRhythms.figures(in: g).contains { beat == nil || $0.span == 1 } }
        DesignSheet(title: beat.map { "Доля \($0 + 1) · ритм" } ?? "Ритм", height: 784, close: { app.sheet = nil }) {
            ScrollViewReader { reader in
                VStack(alignment: .leading, spacing: 16) {
                    // Jump to a section: 127 figures were nine screens of scrolling.
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(groups, id: \.self) { g in
                                Button { withAnimation(Motion.out(Motion.Duration.base)) { reader.scrollTo(g.rawValue, anchor: .top) } } label: {
                                    Chip(text: g.title, style: .muted)
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    if ladder {
                        Text("Сейчас деление ведёт «Лесенка делений» — выбор выключит её")
                            .font(Typo.caption).foregroundStyle(Theme.sharp)
                    }
                    if let beat {
                        Button {
                            metronome.setRhythm(nil, beat: beat)
                            app.sheet = nil
                        } label: {
                            Text("Как у всех долей").font(Typo.inter(15, .medium)).foregroundStyle(Theme.textBody)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(Capsule().fill(Theme.cardFill))
                                .overlay(Capsule().strokeBorder(current == nil ? Theme.textPrimary.opacity(0.7) : Theme.hairline, lineWidth: 1))
                        }
                        .buttonStyle(PressableStyle())
                    } else if let own = metronome.meter.beatRhythms?.compactMap({ $0 }).count, own > 0 {
                        HStack {
                            Text("У \(own) \(ruPlural(own, "доли", "долей", "долей")) свой ритм").font(Typo.inter(14)).foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Button { metronome.clearBeatRhythms() } label: { Chip(text: "Сбросить") }.buttonStyle(PressableStyle())
                        }
                    }
                    if beat == nil {
                        // Swing and the ME-8 second track (the canvas «Размер и деление» has no place for them).
                        SwingCard()
                        PolyTrackSection()
                    }
                    if !recent.isEmpty { section("Недавние", recent, current: current, id: "recent") }
                    ForEach(groups, id: \.self) { group in
                        // A single beat takes only one-beat figures.
                        let items = BeatRhythms.figures(in: group).filter { beat == nil || $0.span == 1 }
                        section(group.title, items, current: current, id: group.rawValue)
                    }
                }
            }
        }
    }

    private func section(_ title: String, _ items: [BeatRhythm], current: BeatRhythm?, id: String) -> some View {
        let denominator = app.metronome.meter.denominator
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(title) · \(items.count)").font(Typo.caption).foregroundStyle(Theme.textTertiary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(items) { r in
                    let selected = current.map { c in c.id == r.id || (c.isPlain && r.isPlain && c.grid == r.grid) } ?? false
                    Button {
                        let metronome = app.metronome
                        if metronome.state.modes.subdivision == .ladder {
                            // Through `modes`: the engine restarts with the ladder off (setting `state` did not reach it).
                            var m = metronome.modes
                            m.subdivision = .none
                            metronome.modes = m
                        }
                        if let beat { metronome.setRhythm(r, beat: beat) } else { metronome.setRhythm(r) }
                        remember(r)
                        app.sheet = nil
                    } label: {
                        VStack(spacing: 2) {
                            RhythmGlyph(rhythm: r, color: selected ? Theme.background : Theme.textPrimary, denominator: denominator)
                                .frame(height: 32)
                            Text(caption(r)).font(Typo.inter(9)).foregroundStyle(selected ? Theme.background.opacity(0.7) : Theme.textTertiary)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .padding(.horizontal, 6).padding(.vertical, 6)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(selected ? AnyShapeStyle(Theme.textPrimary) : AnyShapeStyle(Theme.cardFill)))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(BeatRhythms.spokenName(r))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .id(id)
    }

    /// Small caption under multi-beat and named figures («2 доли», «клаве»).
    private func caption(_ r: BeatRhythm) -> String {
        let name = BeatRhythms.name(r)
        if name != r.shortName && r.group != .values && r.group != .sixteenths && r.group != .triplets { return name }
        switch r.span {
        case 0: return "такт"
        case 1: return ""
        case 2: return "2 доли"
        case 3, 4: return "\(r.span) доли"
        default: return "\(r.span) долей"
        }
    }
}
