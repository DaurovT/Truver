import SwiftUI
import TruverTheory

/// First launch (canvas «Первый запуск», 6.1 п. 4): instrument → why the microphone → system request.
struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 welcome, 1 instrument, 2 microphone (then the system request).
    /// `-onboardingStep N` (debug) opens a given step for screenshots.
    @State private var step = UserDefaults.standard.integer(forKey: "onboardingStep")
    @State private var kind = Kind.guitar
    @State private var strings = 7
    @State private var templateId = "g7-standard-b"
    @State private var frets = 24
    /// «Знакомство» (Features/Tour) between the welcome and the instrument; `-tour N` (debug) opens card N.
    @State private var tourPage: Int? = { let n = UserDefaults.standard.integer(forKey: "tour"); return n > 0 ? n - 1 : nil }()

    enum Kind: String, CaseIterable, Identifiable {
        case guitar = "Гитара", bass = "Бас", ukulele = "Укулеле", mandolin = "Мандолина"
        var id: String { rawValue }
        /// Canvas tile caption.
        var subtitle: String {
            switch self {
            case .guitar: return "6–9 струн"
            case .bass: return "4–6 струн"
            case .ukulele: return "4 струны"
            case .mandolin: return "4 пары струн"
            }
        }
        var stringRange: ClosedRange<Int>? {
            switch self {
            case .guitar: return 6...9
            case .bass: return 4...6
            default: return nil
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                ScreenBackground()
                Group {
                    switch step {
                    case 0: welcome(h).transition(.opacity)
                    case 1: instrument(h).transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    default: microphone(h).transition(.move(edge: .trailing))
                    }
                }
                .animation(Motion.move(reduceMotion), value: step)
                if let tourPage {
                    TourView(mode: .firstRun, page: tourPage) {
                        withAnimation(Motion.move(reduceMotion)) { self.tourPage = nil; step = 1 }
                    }
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    .zIndex(1)
                }
                if step > 0 {
                    // Canvas: the dots row at 64 pt on «Ваш инструмент», at 70 pt on «Зачем микрофон».
                    progress.frame(width: geo.size.width).offset(y: step == 1 ? 64 : 70)
                }
            }
            .frame(width: geo.size.width, height: h, alignment: .topLeading)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    /// Canvas boards are 844 pt high and positioned from the screen top; blocks under the middle keep their distance
    /// to the bottom edge instead, so taller and shorter phones only stretch the gap between them.
    private func fromBottom(_ y: CGFloat, _ h: CGFloat) -> CGFloat { h - (844 - y) }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Capsule().fill(i == step - 1 ? Theme.textPrimary : Color.white.opacity(step == 1 ? 0.25 : 0.2))
                    .frame(width: i == step - 1 ? 22 : 6, height: 6)
            }
        }
        .animation(Motion.move(reduceMotion), value: step)
        .accessibilityLabel("Шаг \(step) из 3")
    }

    // MARK: Step 0 (canvas «Первый запуск — приветствие»)

    private func welcome(_ h: CGFloat) -> some View {
        ZStack(alignment: .top) {
            // Mark 150 at 150 pt, then 28 pt gaps: the wordmark (line height 1 → 64 pt box) and the tagline
            // (17 pt, line height 1.45, max 300 wide).
            VStack(spacing: 28) {
                BrandMark().frame(width: 150, height: 150)
                Wordmark(size: 64).padding(.vertical, -6.75)
                Text("Тюнер, гриф и метроном для гитар на 4–9 струн — и любых строев")
                    .font(Typo.inter(17)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                    .lineSpacing(17 * 1.45 - 17 * 1.2109).padding(.vertical, (17 * 1.45 - 17 * 1.2109) / 2)
                    .frame(maxWidth: 300)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .offset(y: 150)
            // What the app does: three rows of icon 20 + 14 pt text, 10 apart, at 560 pt.
            VStack(alignment: .leading, spacing: 10) {
                feature(.tuner, "Точный тюнер, даже для B0 на 9 струнах")
                feature(.fretboard, "Гаммы и позиции в вашем строе")
                feature(.metronome, "Метроном с режимами для занятий")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .offset(y: fromBottom(560, h))
            VStack(spacing: 6) {
                PrimaryButton(title: "Начать", height: 56, maxWidth: nil) { withAnimation(Motion.move(reduceMotion)) { tourPage = 0 } }
                Text("Бесплатно. Без регистрации и рекламы").font(Typo.caption).foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 24)
            .offset(y: fromBottom(716, h))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func feature(_ icon: AppIcon, _ text: String) -> some View {
        HStack(spacing: 12) {
            Icon(icon, size: 20, lineWidth: 1.6, color: Theme.textSecondary)
            Text(text).font(Typo.inter(14)).foregroundStyle(Theme.textBody)
        }
        .frame(height: 20)
    }

    // MARK: Step 1 (canvas «Первый запуск — инструмент», исправлено)

    private func instrument(_ h: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ваш инструмент").font(Typo.inter(30, .light)).foregroundStyle(Theme.textPrimary)
                Text("Всё можно поменять позже").font(Typo.inter(14)).foregroundStyle(Theme.textSecondary)
            }
            .offset(y: 96)
            // Instrument tiles: 2 columns, 8 apart, 72 pt, radius 16; name 16 semibold + range 12, left-aligned.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                ForEach(Kind.allCases) { k in
                    let selected = k == kind
                    Button {
                        kind = k
                        if let range = k.stringRange { strings = min(max(strings, range.lowerBound), range.upperBound) }
                        templateId = templates.first?.id ?? templateId
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(k.rawValue).font(Typo.inter(16, .semibold)).foregroundStyle(Theme.textPrimary)
                            Text(k.subtitle).font(Typo.caption).foregroundStyle(Theme.textTertiary)
                        }
                        .padding(.horizontal, 17)   // border 1 + padding 16
                        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(selected ? 0.1 : 0.04)))
                        .overlay(RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(selected ? Color(red: 243 / 255, green: 239 / 255, blue: 230 / 255, opacity: 0.7) : Theme.hairline, lineWidth: 1))
                        .contentShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .offset(y: 176)
            // Strings and frets: one card at 340 pt, rows 56 pt.
            if kind.stringRange != nil || fretOptions != nil {
                Card {
                    if let range = kind.stringRange {
                        CardRow(title: "Число струн", minHeight: 57) {
                            ValueStepper(value: "\(strings)", canDecrement: strings > range.lowerBound, canIncrement: strings < range.upperBound,
                                         decrement: { strings -= 1; templateId = templates.first?.id ?? templateId },
                                         increment: { strings += 1; templateId = templates.first?.id ?? templateId })
                        }
                    }
                    if let options = fretOptions {
                        // The neck, positions and paths end at the guitar's last fret (user: «24 или 22 лада»).
                        CardRow(title: "Ладов", minHeight: 57) {
                            Segments(options: options.map { ($0, "\($0)") }, selection: $frets, size: .compact)
                                .frame(width: 170)
                        }
                    }
                }
                .offset(y: 340)
            }
            // Tunings: at 476 pt down to 158 pt above the bottom, scrolling under a 44 pt fade.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionCaption(text: templateCaption)
                    Card {
                        ForEach(Array(templates.enumerated()), id: \.element.id) { index, template in
                            Button { templateId = template.id } label: { templateRow(template) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.bottom, 44)
            }
            .scrollIndicators(.hidden)
            .frame(height: max(0, fromBottom(686, h) - 476))
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [Color(hex: 0x0d0e10, opacity: 0), Color(hex: 0x0c0d0f)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 44).allowsHitTesting(false)
            }
            .offset(y: kind.stringRange != nil || fretOptions != nil ? 476 : 340)
            PrimaryButton(title: "Продолжить", height: 52, maxWidth: nil) {
                if let template = TuningTemplates.template(id: templateId) {
                    app.replaceInstrument(with: template, fretCount: fretOptions == nil ? nil : frets)
                }
                step = 2
            }
            .offset(y: fromBottom(704, h))
            Button {
                app.replaceInstrument(with: TuningTemplates.template(id: "g6-standard-e")!)
                step = 2
            } label: {
                Text("Пропустить — гитара 6 струн, стандарт E").font(Typo.inter(13)).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(y: fromBottom(768, h))
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var templateCaption: String {
        switch kind {
        case .guitar, .bass: return "Строй · \(strings) \(strings < 5 ? "струны" : "струн")"
        default: return "Строй"
        }
    }

    /// A tuning row of the canvas: min height 54, title 15 (semibold when chosen), notes 12, ivory check 20.
    private func templateRow(_ template: TuningTemplate) -> some View {
        let selected = template.id == templateId
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(template.names.ru).font(Typo.inter(15, selected ? .semibold : .regular)).foregroundStyle(Theme.textPrimary)
                Text(template.notes.map { app.noteName($0) }.joined(separator: " ")).font(Typo.caption).foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Green means only «в строю» (brand rule): the selection mark is ivory.
            if selected { Icon(.check, size: 20, lineWidth: 2, color: Theme.textPrimary) }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 55)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
        .contentShape(Rectangle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Common fret counts: guitars 21 / 22 / 24 / 27 (baritone), basses 20 / 21 / 22 / 24.
    private var fretOptions: [Int]? {
        switch kind {
        case .guitar: return [21, 22, 24, 27]
        case .bass: return [20, 21, 22, 24]
        default: return nil
        }
    }

    /// Most played first (the standard tuning leads).
    private var templates: [TuningTemplate] {
        let list = TuningTemplates.all.filter { t in
            switch kind {
            case .guitar: return (t.type == .guitar || t.type == .guitarExtendedHigh) && t.courseCount == strings
            case .bass: return t.type == .bass && t.courseCount == strings
            case .ukulele: return t.type == .ukulele
            case .mandolin: return t.type == .mandolin
            }
        }
        return TuningTemplates.byPopularity(list)
    }

    // MARK: Step 2 → 3 (canvas «Первый запуск — микрофон»)

    private func microphone(_ h: CGFloat) -> some View {
        ZStack(alignment: .top) {
            MiniBezel(size: 200) { Icon(.mic, size: 56, lineWidth: 1.2, color: Theme.textPrimary) }
                .offset(y: 170)
            VStack(spacing: 12) {
                Text("Зачем микрофон").font(Typo.inter(28, .light)).foregroundStyle(Theme.textPrimary)
                // 15 pt, line height 1.5
                Text("Микрофон нужен только тюнеру и проверке игры. Звук обрабатывается на телефоне — не записывается и никуда не отправляется.")
                    .font(Typo.inter(15)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                    .lineSpacing(15 * 1.5 - 15 * 1.2109).padding(.vertical, (15 * 1.5 - 15 * 1.2109) / 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .offset(y: 420)
            PrimaryButton(title: "Продолжить", height: 56, maxWidth: nil) {
                Task {
                    _ = await app.audio.requestMicPermission()
                    app.settings.onboarded = true
                    app.settings.lastTab = .tuner
                    CoachCenter.shared.arm()   // the hints of «Знакомство и обучение» start now
                    app.showOnboarding = false
                }
            }
            .padding(.horizontal, 24)
            .offset(y: fromBottom(740, h))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
