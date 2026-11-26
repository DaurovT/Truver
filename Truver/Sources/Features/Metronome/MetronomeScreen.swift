import SwiftUI
import TruverDSP

/// Metronome by the canvas («Метроном — остановлен / играет / …», 390 × 844). Vertical rhythm under the header
/// (header top 50): beats 108 (+14), status line 162 (+10, 18), chips 186 (+6, 36), knob 222 (290), controls 532
/// (+20, 88), Tap 634 (+14, 60); toasts and the interruption banner at 702 / 698.
struct MetronomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var accentMenuBeat: Int?
    @State private var accentMenuTask: Task<Void, Never>?
    @State private var beatCenters: [Int: CGFloat] = [:]
    @Environment(\.isPhoneLandscape) private var landscape

    private var metronome: MetronomeController { app.metronome }

    var body: some View {
        Group {
            if landscape {
                landscapeBody
            } else if typeSize.isAccessibilitySize {
                largeText
            } else {
                regular
            }
        }
        .overlay { fullScreenFlash }
        .fullScreenCover(isPresented: Binding(get: { metronome.sessionEnd != nil }, set: { if !$0 { metronome.dismissSessionEnd() } })) {
            if let end = metronome.sessionEnd {
                DesignAlert(title: "Занятие закончено", message: end.message,
                            actions: [.init(title: "Ещё 5 мин") { metronome.extendSession() },
                                      .init(title: "Готово", role: .preferred) { metronome.dismissSessionEnd() }],
                            dismiss: { metronome.dismissSessionEnd() })
                    .ignoresSafeArea()
                    .presentationBackground(.clear)
            }
        }
        .transaction { if metronome.sessionEnd != nil || $0.animation == nil { $0.disablesAnimations = true } }
    }

    // MARK: Regular layout

    private var regular: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Метроном") {
                Button { app.sheet = .metroPresets } label: {
                    HeaderChip(text: metronome.state.currentPreset?.name ?? "Пресеты", icon: .chevronDown, iconSize: 12)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Пресет: \(metronome.state.currentPreset?.name ?? "нет")")
            }
            GeometryReader { proxy in
                // Fixed blocks are 310 pt + the knob; the knob gives way on short screens.
                let knob = min(290, max(200, proxy.size.height - 310 - 8))
                VStack(spacing: 0) {
                    beatStrip.padding(.top, 14)
                    statusLine.padding(.top, 10)
                    chipsRow.coachAnchor(CoachCatalog.Anchor.chips).padding(.top, 6)
                    TempoKnob(bpm: metronome.displayBPM, size: knob, dimmed: metronome.isPlaying && metronome.silentBar,
                              onDrag: { metronome.step($0) }, onDoubleTap: { metronome.toggle() })
                        .coachAnchor(CoachCatalog.Anchor.knob)
                        .onLongPressGesture(minimumDuration: 0.5) { app.sheet = .metroModes }
                    controls(minus: 64, play: 88, icon: 24, playIcon: 30).padding(.top, 20)
                    Group {
                        if app.playCheck.isOn {
                            PlayCheckPanel(height: 60)
                        } else {
                            tapButton(height: 60, radius: 18, font: Typo.inter(15, .medium))
                        }
                    }
                    .padding(.top, 14)
                    // Canvas «Прервано звонком»: the banner (698) lies over the tab bar — the root draws it (RootView).
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .frame(width: proxy.size.width)
            }
        }
        .overlay(alignment: .topLeading) { accentMenu(below: 108) }
        // Canvas «Цель достигнута»: the toast sits at 702, under Tap (header top 50 → 652 below the safe area top + 3).
        .overlay(alignment: .top) { toast.padding(.top, 655) }
        .coordinateSpace(name: "metronome")
    }

    private var interruptionBanner: some View { MetronomeInterruptionBanner() }

    // MARK: Landscape (canvas «Метроном — альбом», 844 × 390)

    /// Title 20 at (60, 20); the knob 290 × 0.98 at (70, 54); on the right from x 400, 384 wide, from top 36 and 16
    /// apart: beats (44), the status line, − / play / + (60 / 84), Tap 52.
    private var landscapeBody: some View {
        LandscapeCanvas {
            ZStack(alignment: .topLeading) {
                Text("Метроном").font(Typo.inter(20, .semibold)).foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .board(x: 60, y: 20, width: 300)
                TempoKnob(bpm: metronome.displayBPM, size: 290, dimmed: metronome.isPlaying && metronome.silentBar,
                          caption: "BPM", onDrag: { metronome.step($0) }, onDoubleTap: { metronome.toggle() })
                    .onLongPressGesture(minimumDuration: 0.5) { app.sheet = .metroModes }
                    .scaleEffect(0.98, anchor: .topLeading)
                    .offset(x: 70, y: 54)
                VStack(spacing: 16) {
                    beatStrip
                    if let status = metronome.statusText {
                        Text(status).font(Typo.inter(13)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    }
                    controls(minus: 60, play: 84, icon: 22, playIcon: 28)
                    tapButton(height: 52, radius: 16, font: Typo.inter(15))
                }
                .board(x: 400, y: 36, width: 384)
            }
            .frame(width: 844, height: 390, alignment: .topLeading)
            .overlay(alignment: .topLeading) { accentMenu(below: 80) }
            .overlay(alignment: .top) { toast.padding(.top, 20) }
            .coordinateSpace(name: "metronome")
        }
    }

    // MARK: Beat strip (34 × 44 buttons; bars 28 strong, 18 normal; groups 14 apart, beats 5)

    private var groups: [[Int]] {
        let m = metronome.meter
        let sizes = (m.grouping?.reduce(0, +) == m.numerator ? m.grouping : nil) ?? [m.numerator]
        var result: [[Int]] = []
        var index = 0
        for size in sizes {
            result.append(Array(index..<index + size))
            index += size
        }
        return result
    }

    private var beatStrip: some View {
        GeometryReader { proxy in
            let n = CGFloat(metronome.meter.numerator)
            let gaps = CGFloat(groups.count - 1) * 14 + CGFloat(metronome.meter.numerator - groups.count) * 5
            let width = min(34, (proxy.size.width - gaps) / max(1, n))
            HStack(alignment: .bottom, spacing: 14) {
                ForEach(groups, id: \.self) { group in
                    HStack(alignment: .bottom, spacing: 5) {
                        ForEach(group, id: \.self) { beat in beatBar(beat, width: width) }
                    }
                }
            }
            .frame(width: proxy.size.width, height: 44)
        }
        .frame(height: 44)
        .onLongPressGesture(minimumDuration: 0.5) { app.sheet = .metroMeter }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Доли \(metronome.meter.numerator)/\(metronome.meter.denominator)")
    }

    static func barHeight(_ level: AccentLevel) -> CGFloat {
        switch level {
        case .strong: return 28
        case .normal: return 18
        case .soft: return 11
        case .off: return 4
        }
    }

    static func barFill(_ level: AccentLevel) -> Color {
        switch level {
        case .strong: return Theme.beat.opacity(0.38)
        case .normal: return Color.white.opacity(0.16)
        case .soft: return Color.white.opacity(0.11)
        case .off: return Color.white.opacity(0.06)
        }
    }

    private func beatBar(_ beat: Int, width: CGFloat) -> some View {
        let level = metronome.meter.accents[safe: beat] ?? .normal
        let silent = metronome.isPlaying && metronome.silentBar
        let lit = metronome.litBeat == beat
        let height = Self.barHeight(level)
        // A tap only opens the level menu: changing the accent at once broke the strong beat on every attempt
        // to reach the meter (iPhone UX check).
        return Button {
            showAccentMenu(beat)
        } label: {
            RoundedRectangle(cornerRadius: 3)
                .fill(silent ? Color.white.opacity(0.06) : Self.barFill(level))
                .frame(width: width, height: height)
                .overlay {
                    RoundedRectangle(cornerRadius: 3).fill(Theme.beat)
                        .shadow(color: Theme.beat.opacity(0.9), radius: 6)
                        .shadow(color: Theme.beat.opacity(0.45), radius: 3)
                        .opacity(lit ? 1 : 0)
                        .animation(lit ? nil : .easeOut(duration: 0.18), value: lit)
                }
                .frame(width: width, height: 44, alignment: .bottom)
                .overlay(alignment: .top) {
                    if let own = metronome.beatRhythm(beat) {
                        RhythmGlyph(rhythm: own, color: Theme.textSecondary, denominator: metronome.meter.denominator)
                            .frame(width: max(18, width + 4), height: 20)
                            .offset(y: -6)
                    }
                }
                .contentShape(Rectangle())
                .background(GeometryReader { g in
                    Color.clear.onAppear { beatCenters[beat] = g.frame(in: .named("metronome")).midX }
                        .onChange(of: g.frame(in: .named("metronome")).midX) { _, x in beatCenters[beat] = x }
                })
        }
        .buttonStyle(.plain)
        .animation(Motion.out(Motion.Duration.quick), value: level)
        .accessibilityLabel("Доля \(beat + 1), \(Self.accentName(level))" + (metronome.beatRhythm(beat).map { ", " + BeatRhythms.spokenName($0) } ?? ""))
        .accessibilityHint("Тап — выбрать уровень")
    }

    static func accentName(_ level: AccentLevel) -> String {
        switch level {
        case .strong: return "сильная"
        case .normal: return "обычная"
        case .soft: return "тихая"
        case .off: return "выключена"
        }
    }

    private func showAccentMenu(_ beat: Int) {
        withAnimation(Motion.out(Motion.Duration.quick)) { accentMenuBeat = beat }
        accentMenuTask?.cancel()
        // The menu stays until a choice or a tap outside (6 rows did not fit in 2.5 s — UX check).
    }

    /// «Доля 3 · тап меняет по кругу»: 200 pt menu under the beat with an arrow (canvas «уровень доли»).
    /// - Parameter below: bottom of the beat strip in the «metronome» space (the arrow sits 6 pt under it).
    @ViewBuilder private func accentMenu(below: CGFloat) -> some View {
        if let beat = accentMenuBeat, let x = beatCenters[beat] {
            GeometryReader { proxy in
                let left = min(max(16, x - 116), proxy.size.width - 248)
                // Landscape: the menu would run off the bottom — it opens beside the beat instead.
                let menuTop = landscape ? max(8, below - 140) : below + 14
                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.001)
                        .onTapGesture { withAnimation(Motion.out(Motion.Duration.quick)) { accentMenuBeat = nil } }
                    if !landscape {
                        Rectangle().fill(Color(hex: 0x282a2f, opacity: 0.98))
                            .frame(width: 16, height: 16).rotationEffect(.degrees(45))
                            .offset(x: x - 8, y: below + 6)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Доля \(beat + 1) · уровень").font(Typo.caption).foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                        // Soundbrenner-style: this beat's own note value.
                        Button {
                            accentMenuTask?.cancel()
                            withAnimation(Motion.out(Motion.Duration.quick)) { accentMenuBeat = nil }
                            app.sheet = .metroRhythmBeat(beat)
                        } label: {
                            HStack(spacing: 10) {
                                RhythmGlyph(rhythm: metronome.meter.rhythm(forBeat: beat) ?? metronome.currentRhythm, denominator: metronome.meter.denominator)
                                    .frame(width: 26, height: 18)
                                Text("Ритм доли").font(Typo.inter(15)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                                Spacer()
                                Icon(.chevronRight, size: 14, color: Theme.textTertiary)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 42)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                        ForEach([AccentLevel.strong, .normal, .soft, .off], id: \.self) { level in
                            Button {
                                metronome.setAccent(beat, level)
                                accentMenuTask?.cancel()
                                withAnimation(Motion.out(Motion.Duration.quick)) { accentMenuBeat = nil }
                            } label: {
                                HStack(spacing: 10) {
                                    RoundedRectangle(cornerRadius: 2).fill(Self.swatch(level))
                                        .frame(width: 18, height: Self.swatchHeight(level))
                                        .frame(width: 18, height: 18)
                                    Text(Self.menuName(level)).font(Typo.inter(15)).foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    if metronome.meter.accents[safe: beat] == level {
                                        Icon(.check, size: 16, lineWidth: 2, color: Theme.textPrimary)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .frame(height: 42)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(width: 232)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x282a2f, opacity: 0.98)))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.7), radius: 25, y: 20)
                    .offset(x: left, y: menuTop)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
            .transition(.opacity)
        }
    }

    static func menuName(_ level: AccentLevel) -> String {
        switch level {
        case .strong: return "Сильная"
        case .normal: return "Обычная"
        case .soft: return "Тихая"
        case .off: return "Выключена"
        }
    }

    static func swatch(_ level: AccentLevel) -> Color {
        switch level {
        case .strong: return Theme.beat.opacity(0.7)
        case .normal: return Color.white.opacity(0.35)
        case .soft: return Color.white.opacity(0.25)
        case .off: return Color.white.opacity(0.15)
        }
    }

    static func swatchHeight(_ level: AccentLevel) -> CGFloat {
        switch level {
        case .strong: return 18
        case .normal: return 12
        case .soft: return 7
        case .off: return 3
        }
    }

    // MARK: Status and chips

    private var statusLine: some View {
        Text(metronome.statusText ?? " ")
            .font(Typo.inter(13)).foregroundStyle(Theme.textSecondary)
            // Canvas: the line sits at the top of its 18 pt box (CSS `min-height`), not centred in it.
            .frame(maxWidth: .infinity, minHeight: 18, alignment: .top)
            .contentTransition(.identity)
            .accessibilityHidden(metronome.statusText == nil)
    }

    private var chipsRow: some View {
        // Fits in one line when it can, otherwise scrolls sideways.
        ViewThatFits(in: .horizontal) {
            chipsLine
            ScrollView(.horizontal) { chipsLine.padding(.horizontal, 2) }.scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, minHeight: 36)
        .animation(Motion.out(Motion.Duration.base), value: metronome.chips.map(\.text))
    }

    private var chipsLine: some View {
        HStack(spacing: 8) {
            // Note value, one tap to the grid of values and figures (user: «как в Soundbrenner»).
            RhythmChip()
            // Stage SM: «Проверка игры» — the microphone grades the playing.
            Button { app.sheet = .playCheck } label: {
                Chip(text: "Проверка", icon: .mic, style: app.playCheck.isOn ? .emphasized : .plain, size: .large)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Проверка игры")
            // The meter is always visible and opens «Размер и деление».
            Button { app.sheet = .metroMeter } label: {
                Chip(text: "\(metronome.meter.numerator)/\(metronome.meter.denominator)", size: .large)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Размер \(metronome.meter.numerator)/\(metronome.meter.denominator)"
                                + ((metronome.meter.grouping?.count ?? 0) > 1 ? ", группы " + metronome.meter.grouping!.map(String.init).joined(separator: "+") : ""))
            let mode = metronome.modeChip
            Button { app.sheet = .metroModes } label: {
                Chip(text: mode.text, icon: mode.kind == .mode && [.speedUp, .twoForward].contains(metronome.modeChoice) ? .arrowUp : nil,
                     style: mode.kind == .mode ? .emphasized : .plain, size: .large)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(mode.kind == .mode ? "Режим: \(mode.text.lowercased())" : "Режимы")
            ForEach(metronome.chips) { chip in
                Button {
                    switch chip.action {
                    case .modes?: app.sheet = .metroModes
                    case .timer?: app.sheet = .metroTimer
                    case .meter?: app.sheet = .metroMeter
                    case nil: break
                    }
                } label: {
                    Chip(text: chip.text, icon: Self.icon(chip.kind), style: Self.style(chip.kind), size: .large)
                }
                .buttonStyle(PressableStyle())
                .disabled(chip.action == nil)
            }
        }
        .fixedSize()
    }

    static func icon(_ kind: MetronomeChip.Kind) -> AppIcon? {
        switch kind {
        case .plain: return nil
        case .mode: return .arrowUp
        case .target: return .check
        case .timer: return .timer
        case .warning: return .warning
        }
    }

    static func style(_ kind: MetronomeChip.Kind) -> Chip.Style {
        switch kind {
        case .plain, .timer: return .plain
        case .mode: return .emphasized
        case .target: return .positive
        case .warning: return .muted
        }
    }

    // MARK: Controls

    private func controls(minus: CGFloat, play: CGFloat, icon: CGFloat, playIcon: CGFloat) -> some View {
        HStack {
            RoundIconButton(icon: .minus, size: minus, iconSize: icon, label: "Медленнее на 1") { metronome.step(-1) }
                .overlay { if metronome.atMinimum { Circle().fill(Theme.background.opacity(0.6)).frame(width: minus, height: minus).allowsHitTesting(false) } }
                .disabled(metronome.atMinimum)
            Spacer()
            PrimaryRoundButton(icon: metronome.isPlaying ? .stop : .play, size: play, iconSize: playIcon, label: metronome.isPlaying ? "Стоп" : "Старт") { metronome.toggle() }
            Spacer()
            RoundIconButton(icon: .plus, size: minus, iconSize: icon, label: "Быстрее на 1") { metronome.step(1) }
                .overlay { if metronome.atMaximum { Circle().fill(Theme.background.opacity(0.6)).frame(width: minus, height: minus).allowsHitTesting(false) } }
                .disabled(metronome.atMaximum)
        }
    }

    private func tapButton(height: CGFloat, radius: CGFloat, font: Font) -> some View {
        Button { metronome.tapTempo() } label: {
            Text("Tap — стучите в ритм").font(font).foregroundStyle(Theme.textBody)
                .frame(maxWidth: .infinity, minHeight: height)
                .background(RoundedRectangle(cornerRadius: radius).fill(Theme.cardFill))
                .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Tap tempo — стучите в ритм")
    }

    /// Canvas toast (radius 16, 13 medium); a reached target is green — icon and text.
    @ViewBuilder private var toast: some View {
        if let toast = metronome.toast {
            let color = toast.icon == .check ? Theme.inTune : Theme.textBody
            HStack(spacing: 10) {
                Icon(toast.icon, size: 16, lineWidth: toast.icon == .check ? 2 : 1.6, color: toast.icon == .check ? Theme.inTune : Theme.beat)
                Text(toast.text).font(Typo.inter(13, .medium)).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
            }
            // padding 11 × 16 inside a 1 pt CSS border (the stroke is drawn inside here).
            .padding(.horizontal, 17).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: 0x26282d, opacity: 0.96)).shadow(color: .black.opacity(0.6), radius: 15, y: 14))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairlineStrong, lineWidth: 1))
            .padding(.horizontal, 24)
            .accessibilityElement(children: .combine)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder private var fullScreenFlash: some View {
        if metronome.state.flash == .screen {
            Theme.beat.opacity(metronome.flashOn ? 0.16 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(metronome.flashOn ? nil : .easeOut(duration: 0.18), value: metronome.flashOn)
        }
    }

    // MARK: Large text (canvas «Метроном — крупный шрифт»: the knob gives way to the number and buttons)

    /// Title 34 bold (top 50), «Риф 7/8 · Разгон» 20 (116), the tempo 120 light (180) with «BPM» 22, − / play / +
    /// 80 / 100 (380), Tap 76 (510), the note 15 (606). Sizes are fixed: the layout already is the large one.
    private var largeText: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Метроном").font(Typo.fixed(34, .bold)).foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .frame(height: 41.2).padding(.top, 3)
                Text(largeSubtitle).font(Typo.fixed(20)).foregroundStyle(Theme.textSecondary)
                    .frame(height: 24.2).padding(.top, 24.8)
                VStack(spacing: 0) {
                    Text("\(Int(metronome.displayBPM))").font(Typo.fixed(120, .light)).foregroundStyle(Theme.textPrimary)
                        .frame(height: 120)
                    Text("BPM").font(Typo.fixed(22)).foregroundStyle(Theme.textSecondary).frame(height: 26.6)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 39.8)
                .accessibilityElement(children: .combine)
                controls(minus: 80, play: 100, icon: 30, playIcon: 36).padding(.top, 53.4)
                tapButton(height: 76, radius: 20, font: Typo.fixed(22)).padding(.top, 30)
                if metronome.interrupted {
                    interruptionBanner.padding(.top, 20)
                } else {
                    Text("Ручка заменена числом и кнопками: при крупном шрифте их легче нажать")
                        .font(Typo.fixed(15)).foregroundStyle(Theme.textTertiary).lineSpacing(21 - 18.15)
                        .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                        .padding(.top, 21.43)
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// «Риф 7/8 · Разгон»: the preset (or the meter) and the mode.
    private var largeSubtitle: String {
        var parts = [metronome.state.currentPreset?.name ?? "\(metronome.meter.numerator)/\(metronome.meter.denominator)"]
        if metronome.modeChip.kind == .mode { parts.append(metronome.modeChip.text) }
        return parts.joined(separator: " · ")
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// The interruption banner (canvas «Прервано звонком»). The root draws it above the tab bar, landscape in place.
struct MetronomeInterruptionBanner: View {
    @Environment(AppModel.self) private var app
    private var metronome: MetronomeController { app.metronome }

    /// «Остановлено звонком. Продолжить с 150 BPM, такт 12» + «Продолжить» (canvas: radius 14, orange tint).
    var body: some View {
        HStack(spacing: 10) {
            Icon(.warning, size: 18, color: Theme.sharp)
            Text(metronome.interruptionText)
                .font(Typo.inter(13)).foregroundStyle(Theme.textBody).lineSpacing(17.55 - 15.73)
                .padding(.vertical, 0.91)   // the half-leading of line-height 1.35
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button { metronome.start() } label: {
                Text("Продолжить").font(Typo.inter(15, .semibold)).foregroundStyle(Theme.background)
                    .padding(.horizontal, 18).frame(height: 36)
                    .background(Capsule(style: .circular).fill(Theme.primaryFill))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.leading, 15).padding(.trailing, 13).padding(.vertical, 11)   // padding 10 12 10 14 + the 1 pt border
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.sharp.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.sharp.opacity(0.35), lineWidth: 1))
        .fixedSize(horizontal: false, vertical: true)
    }
}
