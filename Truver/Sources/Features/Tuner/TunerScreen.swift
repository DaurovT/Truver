import CoreText
import SwiftUI
import TruverDSP
import TruverTheory
#if os(iOS)
import AVFoundation
import MediaAccessibility
import UIKit
#else
import AppKit
#endif

/// Tuner (canvas «Тюнер», 6.2.4; corrected «Fix…» boards of 2026-11-25): header, dial with the needle on the
/// scale, status line (or the state's action / strobe strips), large string keys with the octave inline (or the
/// chromatic note strip), mode segments with the reference tone and «Ещё» (strobe, stage, noise gate).
struct TunerScreen: View {
    @Environment(AppModel.self) private var app
    @State private var showStage = false
    @Environment(\.isPhoneLandscape) private var landscape

    private var tuner: TunerController { app.tuner }

    @Environment(\.dynamicTypeSize) private var typeSize

    private var largeLayout: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-tunerLarge") { return true }
        #endif
        return typeSize.isAccessibilitySize
    }

    var body: some View {
        Group {
            if landscape { landscapeBody } else if largeLayout { largeText } else { portrait }
        }
        // The canvas sets `font-variant-numeric: tabular-nums` on the whole board: «−14 ц», «109,1 Гц», octaves.
        .monospacedDigit()
        .overlay(alignment: .top) { if !landscape { noticeBanner } }
        #if os(iOS)
        .fullScreenCover(isPresented: stageBinding) { stage }
        #else
        .sheet(isPresented: stageBinding) { stage.frame(minWidth: 640, minHeight: 480) }
        #endif
        #if DEBUG
        .onAppear { if ProcessInfo.processInfo.arguments.contains("-tunerStage") { tuner.showStage = true } }
        #endif
    }

    private var stageBinding: Binding<Bool> {
        Binding(get: { tuner.showStage }, set: { tuner.showStage = $0 })
    }

    /// TU-12 «Сценический режим» (canvas «Тюнер — сцена»): the note and the colour fill the screen.
    private var stage: some View {
        TunerStageView(center: dialCenter, cents: needleCents, inTune: voiceInTune || (needleCents.map { abs($0) <= 3 } ?? false),
                       tuningName: app.title) { tuner.showStage = false }
            .environment(app)
    }

    // MARK: Portrait

    private var portrait: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Тюнер", leading: a4Chip) {
                Button { app.showSettings = true } label: { HeaderChip(text: chipInputName, icon: inputIcon) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Вход: \(inputName)")
            }
            GeometryReader { geo in
                // Canvas rows below the header (94): dial +12, status +350, strings +406, modes +490; 8–9 strings
                // in two rows: strings +398, modes +538. The dial takes what is left, at most 320 as on 390 × 844.
                let twoRows = StringGrid.rows(app.tuning.openCents.count) > 1
                let fixed: CGFloat = twoRows ? 12 + 66 + 122 + 18 + 44 : 12 + 74 + 58 + 26 + 44
                let dial = max(180, min(320, geo.size.width - 70, geo.size.height - fixed))
                VStack(spacing: 0) {
                    dialView
                        .frame(width: dial, height: dial)
                        .modifier(TunerVoiceOver(value: voiceValue, inTune: voiceInTune, cents: voiceCents) { up in
                            stepString(up)
                        })
                        .padding(.top, 12)
                        .animation(Motion.reward(false), value: showsDone)
                    middleRow(width: geo.size.width - 40)
                        .frame(height: twoRows ? 66 : 74, alignment: .top)
                    Group {
                        if showsChromaticStrip { ChromaticStrip(current: chromaticCurrent, highlighted: chromaticHighlighted) } else { StringGrid().coachAnchor(CoachCatalog.Anchor.tunerStrings) }
                    }
                    .padding(.horizontal, 20)
                    modeRow
                        .padding(.horizontal, 20)
                        .padding(.top, twoRows ? 18 : 26)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var dialView: some View {
        TunerDial(center: dialCenter, needle: strobeOn ? nil : needleCents, color: dialColor, bandCents: bandCents,
                  glow: showsDone, phase: tuner.strobe?.angle, strobeView: strobeOn,
                  progress: referenceProgress, countdownUntil: demo == nil && tuner.isReferencePlaying ? tuner.referenceUntil : nil,
                  frozen: demo != nil, bandAngle: demoBandAngle)
    }

    /// Between the dial and the strings (canvas: dial bottom + 12 … + 74): the status line at +18 (a 24 pt box,
    /// the 17 pt line at its top, a long hint runs onto a second line), the state's action at +12 or the strobe
    /// strips at +16.
    @ViewBuilder private func middleRow(width: CGFloat) -> some View {
        if micUnavailable {
            actionView.padding(.top, 12)
        } else if strobeOn && hasReading {
            StrobeStrips(phase: demo == nil ? (tuner.strobe?.angle ?? 0) : 0)
                .padding(.horizontal, 20)
                .padding(.top, 16)
        } else {
            Text(typeSize == .large ? Self.greedyLines(status.text, font: Typo.Weight.medium.rawValue, size: 17, width: width) : status.text)
                .font(Typo.status)
                .foregroundStyle(status.color)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .frame(height: 24, alignment: .top)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .contentTransition(.identity)
                .animation(Motion.out(Motion.Duration.quick), value: status.color)
        }
    }

    /// Greedy line breaks, as the canvas (browser) wraps: SwiftUI moves a lone last word to the next line together with
    /// the one before it («…другие ноты / не мешают»), the canvas keeps «…другие ноты не / мешают».
    static func greedyLines(_ text: String, font name: String, size: CGFloat, width: CGFloat) -> String {
        let font = CTFontCreateWithName(name as CFString, size, nil)
        let string = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let typesetter = CTTypesetterCreateWithAttributedString(string)
        let ns = text as NSString
        var lines: [String] = []
        var start = 0
        while start < ns.length {
            let count = CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
            guard count > 0 else { break }
            lines.append(ns.substring(with: NSRange(location: start, length: count)).trimmingCharacters(in: .whitespaces))
            start += count
        }
        return lines.joined(separator: "\n")
    }

    // MARK: VoiceOver (canvas «Тюнер — VoiceOver», 6.1 п. 15)

    /// «A2, ниже на 14 центов» / «A2, в строю» / «Сыграйте струну».
    private var voiceValue: String {
        guard case .reading(let r) = tuner.display, !micUnavailable else { return status.text.isEmpty ? "Нет показаний" : status.text }
        let (name, octave) = noteParts(r)
        let note = name.replacingOccurrences(of: "♯", with: " диез").replacingOccurrences(of: "♭", with: " бемоль") + octave
        if r.isInTune { return "\(note), в строю" }
        let c = Int(abs(r.target.deviationCents).rounded())
        let word = c % 10 == 1 && c % 100 != 11 ? "цент" : ((2...4).contains(c % 10) && !(12...14).contains(c % 100) ? "цента" : "центов")
        return "\(note), \(r.target.deviationCents < 0 ? "ниже" : "выше") на \(c) \(word)"
    }

    private var voiceInTune: Bool {
        if let demo { return demo.inTune }
        if case .reading(let r) = tuner.display { return r.isInTune }
        return false
    }

    private var voiceCents: Double? {
        if case .reading(let r) = tuner.display { return r.target.deviationCents }
        return nil
    }

    /// Swipe up / down on the dial: the next / previous string in manual mode.
    private func stepString(_ up: Bool) {
        let n = app.tuning.openCents.count
        let current: Int = { if case .manual(let m) = tuner.mode { return m.course }; return tuner.lastString?.course ?? 0 }()
        let next = min(n - 1, max(0, current + (up ? 1 : -1)))
        tuner.mode = .manual(StringRef(course: next))
    }

    // MARK: Large text (canvas «Тюнер — крупный шрифт», FixTunerLarge)

    /// Fixed sizes (the layout is already the large one): header 28 pt with two 48 pt buttons (input, settings),
    /// dial 320 × 0.875, status 28 semibold with «109,1 Гц · цель 110» 18 pt under it, strings three in a row
    /// (74 pt, 28 semibold with a 16 pt octave), modes 46 pt at 19 semibold.
    private var largeText: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Тюнер").font(Typo.fixed(28, .semibold)).foregroundStyle(Theme.textPrimary).accessibilityAddTraits(.isHeader)
                Spacer()
                RoundIconButton(icon: inputIcon, size: 48, iconSize: 22, label: "Вход: \(inputName)") { app.showSettings = true }
                RoundIconButton(icon: .gear, size: 48, iconSize: 22, label: "Настройки") { app.showSettings = true }
            }
            .frame(height: 48).padding(.horizontal, 20).padding(.top, ScreenHeader<EmptyView>.topPadding + 2)
            ScrollView {
                VStack(spacing: 0) {
                    TunerDial(center: largeCenter.center, needle: strobeOn ? nil : needleCents, color: dialColor, bandCents: bandCents,
                              glow: showsDone, phase: tuner.strobe?.angle, strobeView: strobeOn, progress: referenceProgress,
                              countdownUntil: demo == nil && tuner.isReferencePlaying ? tuner.referenceUntil : nil, frozen: demo != nil,
                              bandAngle: demoBandAngle)
                        .frame(width: 320, height: 320)
                        .scaleEffect(0.875)
                        .frame(width: 280, height: 280)
                        .padding(.top, 16)
                    VStack(spacing: 4) {
                        Text(status.text.isEmpty ? " " : status.text)
                            .font(Typo.fixed(28, .semibold)).foregroundStyle(status.color)
                            .multilineTextAlignment(.center)
                        if !largeCenter.detail.isEmpty {
                            Typo.notes(largeCenter.detail, size: 18, fixed: true).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 86, alignment: .top)
                    .padding(.top, 12)
                    if micUnavailable {
                        actionView.padding(.bottom, 16)
                    }
                    LargeStringGrid().padding(.horizontal, 20)
                    LargeSegments(selection: Binding(get: { tuner.choice }, set: { tuner.choice = $0 }))
                        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 16)
                }
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// The dial without the Hz line (it moves under the status in large text).
    private var largeCenter: (center: DialCenter, detail: String) {
        let c = dialCenter
        if case let .note(name, octave, cents, color, detail, dimmed) = c {
            // «109,1 Гц · цель 110» (canvas): whole numbers without «,0».
            let hz = detail.replacingOccurrences(of: #"(\d),0(?!\d)"#, with: "$1", options: .regularExpression)
            return (.note(name: name, octave: octave, cents: cents, centsColor: color, detail: "", dimmed: dimmed), hz)
        }
        return (c, "")
    }

    // MARK: Landscape (canvas «Тюнер — альбом», LandTuner 844 × 390)

    /// Title 20 semibold at (60, 20); the dial 320 × 0.97 at (60, 52); on the right from x 400, 384 wide, from 40:
    /// status 20 medium, strings in one row, mode segments, «строй · вход» caption — 14 apart.
    private var landscapeBody: some View {
        LandscapeCanvas {
            ZStack(alignment: .topLeading) {
                Text("Тюнер").font(Typo.inter(20, .semibold)).foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .board(x: 60, y: 20, width: 300)
                dialView
                    .frame(width: 320, height: 320)
                    .scaleEffect(0.97, anchor: .topLeading)
                    .animation(Motion.reward(false), value: showsDone)
                    .offset(x: 60, y: 52)
                VStack(alignment: .leading, spacing: 14) {
                    if micUnavailable {
                        landscapeAction
                    } else if strobeOn && hasReading {
                        StrobeStrips(phase: demo == nil ? (tuner.strobe?.angle ?? 0) : 0)
                    } else {
                        Text(status.text.isEmpty ? " " : status.text)
                            .font(Typo.inter(20, .medium))
                            .foregroundStyle(status.color)
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .fixedSize(horizontal: false, vertical: true)
                            .contentTransition(.identity)
                            .animation(Motion.out(Motion.Duration.quick), value: status.color)
                    }
                    if showsChromaticStrip { ChromaticStrip(current: chromaticCurrent, highlighted: chromaticHighlighted) } else { StringGrid() }
                    SegmentedPill(options: [(TunerController.Choice.auto, "Авто"), (.manual, "Ручной"), (.chromatic, "Хром.")],
                                  selection: Binding(get: { tuner.choice }, set: { tuner.choice = $0 }))
                    Button { app.sheet = .tunings } label: {
                        Text("\(app.title) · \(inputName)")
                            .font(Typo.caption).foregroundStyle(Theme.textTertiary).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Строй: \(app.tuning.name)")
                }
                .board(x: 400, y: 40, width: 384)
            }
        }
    }

    @ViewBuilder private var landscapeAction: some View {
        if tuner.permission == .restricted {
            Text("Изменить доступ может только администратор устройства. Метроном и гриф работают")
                .font(Typo.caption).foregroundStyle(Theme.textTertiary)
        } else if let action = stateAction {
            PrimaryButton(title: action.title, icon: action.icon, height: 46, maxWidth: action.width, action: action.perform)
        }
    }

    // MARK: Header

    private var a4Chip: AnyView? {
        guard abs(app.a4 - 440) > 0.01 else { return nil }
        return AnyView(HeaderChip(text: "A4 · \(Int(app.a4)) Гц", tint: Theme.sharp))
    }

    /// "Микрофон" for the built-in microphone, otherwise the interface's name.
    private var inputName: String {
        if let name = demo?.input { return name }
        #if os(iOS)
        if let input = AVAudioSession.sharedInstance().currentRoute.inputs.first, input.portType != .builtInMic {
            return input.portName
        }
        #endif
        return "Микрофон"
    }

    /// Canvas «Вход переключён»: the chip shows the interface's first word («Focusrite»).
    private var chipInputName: String {
        let name = inputName
        guard name != "Микрофон", name.count > 10, let first = name.split(separator: " ").first else { return name }
        return String(first)
    }

    private var inputIcon: AppIcon { inputName == "Микрофон" ? .mic : .audioInterface }

    // MARK: Notices (canvas «Тюнер — Bluetooth», «Интерфейс отключён», «Вход переключён»)

    @ViewBuilder private var noticeBanner: some View {
        if let notice = demo?.notice ?? tuner.notice {
            TunerNoticeView(notice: notice,
                            dismiss: { tuner.notice = nil },
                            speaker: { tuner.routeToSpeaker() })
                // Canvas: 104 from the top of the board, the safe area (47) included.
                .padding(.top, 57)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: State

    private var demo: TunerDemo? {
        #if DEBUG
        return TunerDemo.current
        #else
        return nil
        #endif
    }

    /// The canvas renders of sheet boards catch the band at another moment — a whole dash period away (0).
    private var demoBandAngle: Double { app.sheet == nil ? (demo?.bandAngle ?? 0) : 0 }

    private var showsDone: Bool {
        if let demo { return demo.done }
        guard tuner.allTuned else { return false }
        if case .idle = tuner.display { return true }
        return false
    }

    private var micUnavailable: Bool {
        if let demo { return demo.action != nil }
        return micBlocked || tuner.needsMicrophoneButton || tuner.error != nil
    }
    private var micBlocked: Bool { tuner.permission == .denied || tuner.permission == .restricted }

    private var hasReading: Bool {
        if let demo { return demo.cents != nil }
        if case .reading = tuner.display { return !tuner.isReferencePlaying }
        return false
    }

    /// TU-10: the strobe view replaces the needle by strips under the dial.
    private var strobeOn: Bool { demo?.strobe ?? tuner.strobeView }

    /// Deviation shown by the needle (and the stage marker): a string or a chromatic-mode note.
    private var needleCents: Double? {
        if let demo { return demo.cents }
        guard case .reading(let r) = tuner.display, !tuner.isReferencePlaying, !micUnavailable else { return nil }
        if case .chromatic = r.target, tuner.mode != .chromatic { return nil }
        return max(-50, min(50, r.target.deviationCents))
    }

    /// Colour of the needle and the strobe band; nil — the idle band.
    private var dialColor: Color? {
        if let demo { return demo.color }
        if showsDone { return Theme.inTune }
        guard needleCents != nil, case .reading(let r) = tuner.display else { return nil }
        return Theme.deviationColor(r.target.deviationCents, inTune: r.isInTune)
    }

    /// Strobe band speed: only while a reading is not in tune.
    private var bandCents: Double? {
        if demo != nil { return nil }
        guard let c = needleCents, case .reading(let r) = tuner.display, !r.isInTune else { return nil }
        return c
    }

    private var referenceProgress: Double? {
        // The canvas render: 0.05 s into the 3 s countdown.
        if let demo { return demo.center.isReference ? 1 - 0.05 / 3 : nil }
        return nil
    }

    private var dialCenter: DialCenter {
        if let demo { return demo.center }
        if tuner.permission == .restricted {
            return .message(icon: .lock, iconColor: Theme.textSecondary, title: "Доступ ограничен",
                            detail: "Микрофон запрещён профилем или родительским контролем")
        }
        if tuner.permission == .denied {
            return .message(icon: .micOff, iconColor: Theme.sharp, title: "Нужен микрофон", detail: "Тюнер слышит струну. Звук не записывается")
        }
        if tuner.needsMicrophoneButton {
            return .message(icon: .micOff, iconColor: Theme.textSecondary, title: "Микрофон выключен", detail: "Сейчас играет метроном")
        }
        if tuner.error != nil {
            return .message(icon: .warning, iconColor: Theme.sharp, title: "Звук недоступен", detail: "Микрофон занят другим приложением или звонком")
        }
        if tuner.isReferencePlaying, let ref = tuner.referenceString {
            let pitch = app.tuning.openPitch(course: ref.course, string: ref.string)
            return .reference(title: "Эталон \(app.stringName(ref))",
                              detail: "\(hz(pitch.frequency(a4: app.a4))) Гц · анализ на паузе")
        }
        if showsDone {
            let total = app.tuning.openCents.count
            return .done(detail: "\(total) из \(total) струн в строю")
        }
        switch tuner.display {
        case .listening:
            return .listening
        case .outOfRange:
            return .message(icon: .warning, iconColor: Theme.textBody, title: "Вне диапазона", detail: "Ниже 25 Гц или выше последнего лада")
        case .idle:
            if let last = tuner.lastReading {
                let (name, octave) = noteParts(last)
                return .note(name: name, octave: octave, cents: "", centsColor: .clear, detail: "", dimmed: true)
            }
            // Canvas «Ожидание»: the first string still to tune, dimmed, with «начните с 6-й струны».
            let courses = app.tuning.openCents.count
            let course = (0..<courses).first { !tuner.tuned.contains(StringRef(course: $0)) } ?? 0
            let (name, octave) = parts(app.tuning.spelledNotes[safe: course] ?? SpelledNote(NoteName(.e), octave: 2))
            let detail = tuner.mode == .chromatic ? "" : "начните с \(courses - course)-й струны"
            return .note(name: name, octave: octave, cents: "", centsColor: .clear, detail: detail, dimmed: true)
        case .reading(let r):
            let (name, octave) = noteParts(r)
            if strobeOn, abs(r.target.deviationCents) < 100 {
                let c = r.target.deviationCents
                let line = r.isInTune ? "полосы почти стоят" : (c < 0 ? "ниже — подтяните" : "выше — ослабьте")
                return .strobeNote(name: name, octave: octave, line: "\(centsText(c)) · \(line)",
                                   color: Theme.deviationColor(c, inTune: r.isInTune))
            }
            switch r.target {
            case let .string(ref, target, deviation):
                let color = Theme.deviationColor(deviation, inTune: r.isInTune)
                if abs(deviation) >= 100 {
                    // Manual mode far from the target: the dial keeps the target, the line names the note played.
                    return .note(name: name, octave: octave, cents: tones(deviation), centsColor: color,
                                 detail: "сейчас \(app.chromaticName(r.pitch)) · \(hz(r.frequency)) Гц")
                }
                let strings = app.instrument.courses[ref.course].strings.count
                let detail = strings > 1 ? "\(hz(r.frequency)) Гц · струна \(ref.string + 1) из \(strings)"
                    : "\(hz(r.frequency)) Гц · цель \(hz(target.frequency(a4: app.a4)))"
                return .note(name: name, octave: octave, cents: centsText(deviation), centsColor: color, detail: detail)
            case let .chromatic(_, deviation, hint):
                if tuner.mode == .chromatic {
                    return .note(name: name, octave: octave, cents: centsText(deviation),
                                 centsColor: Theme.deviationColor(deviation, inTune: r.isInTune), detail: "\(hz(r.frequency)) Гц")
                }
                let detail = hint.map { "ближайшая \(app.stringName($0.string)) · \(signed(Int($0.deviationCents.rounded()))) ц" }
                    ?? "\(hz(r.frequency)) Гц"
                return .note(name: name, octave: octave, cents: "вне строя", centsColor: Theme.textSecondary, detail: detail)
            }
        }
    }

    private var status: (text: String, color: Color) {
        if let demo { return demo.status }
        if micUnavailable { return ("", Theme.textBody) }
        if tuner.isReferencePlaying {
            return ("Звучит эталон · \(max(1, tuner.referenceSecondsLeft)) с", Theme.textBody)
        }
        if showsDone { return ("Все струны в строю", Theme.inTune) }
        switch tuner.display {
        case .idle: return (tuner.mode == .chromatic ? "Сыграйте ноту" : "Сыграйте струну", Theme.textBody)
        case .listening: return ("Дайте струне прозвучать", Theme.textBody)
        case .outOfRange: return ("Сыграйте открытую струну", Theme.textBody)
        case .reading(let r):
            if strobeOn { return ("", Theme.textBody) }
            switch r.target {
            case let .string(ref, _, deviation):
                let paired = app.instrument.courses[ref.course].strings.count > 1
                let number = app.instrument.courses.count - ref.course
                if r.isInTune {
                    if paired { return ("Курс \(ref.course + 1) в строю", Theme.inTune) }
                    // Canvas «Ручной»: the mode explains itself once the string is in tune.
                    if case .manual = tuner.mode { return ("Ручной: только \(app.stringName(ref)) — другие ноты не мешают", Theme.inTune) }
                    return ("В строю", Theme.inTune)
                }
                if abs(deviation) >= 100 {
                    let verb = deviation < 0 ? "подтяните" : "ослабьте"
                    return ("Струна \(number) · \(verb) на \(tones(deviation).dropFirst())", Theme.deviationColor(deviation))
                }
                return deviation < 0 ? ("Ниже — подтяните", Theme.flat) : ("Выше — ослабьте", Theme.sharp)
            case .chromatic:
                return tuner.mode == .chromatic ? ("Хроматический: любая нота, не только струны строя", Theme.textBody)
                    : ("Нота не из этого строя", Theme.textBody)
            }
        }
    }

    // MARK: Chromatic strip (canvas «Тюнер — хроматический»)

    private var showsChromaticStrip: Bool { (demo?.choice ?? tuner.choice) == .chromatic }

    /// Pitch class of the note in the middle of the strip.
    private var chromaticCurrent: Int {
        if let demo, let pc = demo.chromaticPitchClass { return pc }
        if case .reading(let r) = tuner.display, case let .chromatic(nearest, _, _) = r.target { return nearest.pitchClass }
        if let last = tuner.lastReading, case let .chromatic(nearest, _, _) = last.target { return nearest.pitchClass }
        return 9
    }

    private var chromaticHighlighted: Bool {
        if demo != nil { return true }
        if case .reading = tuner.display { return true }
        return false
    }

    // MARK: Actions

    private var stateAction: (title: String, icon: AppIcon?, width: CGFloat, perform: () -> Void)? {
        if let demo { return demo.action.map { ($0.title, nil, $0.width, {}) } }
        if tuner.permission == .restricted { return nil }
        if tuner.permission == .denied {
            return ("Разрешить микрофон", nil, 250, openSettings)
        }
        if tuner.needsMicrophoneButton {
            return ("Включить микрофон", .mic, 250, { Task { await tuner.start(confirmedGap: true) } })
        }
        if tuner.error != nil {
            return ("Повторить", nil, 200, { Task { await tuner.start(confirmedGap: true) } })
        }
        return nil
    }

    /// Canvas «Нет доступа» / «Звук недоступен»: a 46 pt ivory button (250 / 200 wide) 12 pt under the dial.
    @ViewBuilder private var actionView: some View {
        if tuner.permission == .restricted && demo == nil {
            // Nothing the user can do here (canvas «доступ ограничен»): only an explanation, no button.
            Text("Изменить доступ может только администратор устройства. Метроном и гриф работают")
                .font(Typo.caption).foregroundStyle(Theme.textTertiary).multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        } else if let action = stateAction {
            PrimaryButton(title: action.title, icon: action.icon, height: 46, maxWidth: action.width, action: action.perform)
                .frame(width: action.width)
        }
    }

    private var modeRow: some View {
        HStack(spacing: 10) {
            SegmentedPill(options: [(TunerController.Choice.auto, "Авто"), (.manual, "Ручной"), (.chromatic, "Хром.")],
                          selection: Binding(get: { demo?.choice ?? tuner.choice }, set: { tuner.choice = $0 }))
            RoundIconButton(icon: .waveform, size: 44, iconSize: 20, label: "Эталонный тон") {
                tuner.playReference(tuner.referenceTarget)
            }
            .coachAnchor(CoachCatalog.Anchor.tunerReference)
            Button { app.sheet = .tunerPro } label: {
                MoreIcon()
                    .frame(width: 44, height: 44)
                    .background(RoundButtonFace(size: 44))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Ещё: строб, сцена, порог шума")
            .coachAnchor(CoachCatalog.Anchor.tunerMore)
        }
    }

    // MARK: Formatting

    private func parts(_ note: SpelledNote) -> (String, String) {
        (app.formatter.string(note.name), String(note.octave))
    }

    private func noteParts(_ r: TunerReading) -> (String, String) {
        switch r.target {
        case let .string(ref, _, _):
            let main = app.tuning.spelledNotes[ref.course]
            return parts(SpelledNote(main.name, midi: app.tuning.openPitch(course: ref.course, string: ref.string).nearestMIDI))
        case let .chromatic(nearest, _, _):
            let flats = app.tuning.spelledNotes.contains { $0.name.accidental < 0 }
            return parts(SpelledNote(NoteName.simpleSpelling(ofPitchClass: nearest.pitchClass, preferFlats: flats), midi: nearest.nearestMIDI))
        }
    }

    /// Decimal comma (canvas «109,1 Гц · цель 110,0»).
    private func hz(_ f: Double) -> String {
        (f < 100 ? String(format: "%.2f", f) : String(format: "%.1f", f)).replacingOccurrences(of: ".", with: ",")
    }

    private func signed(_ v: Int) -> String { v > 0 ? "+\(v)" : v < 0 ? "−\(-v)" : "0" }

    /// Whole cents (motion spec: rounded to 1 c).
    private func centsText(_ cents: Double) -> String {
        // TU-10: in the strobe view a steady note reads to a tenth of a cent from the phase.
        if tuner.strobeView, let s = tuner.strobe, s.isStable, abs(s.cents) < 50 {
            let v = (s.cents * 10).rounded() / 10
            let text = String(format: "%.1f", abs(v)).replacingOccurrences(of: ".", with: ",")
            return (v > 0 ? "+" : v < 0 ? "−" : "") + text + " ц"
        }
        return "\(signed(Int(cents.rounded()))) ц"
    }

    /// Large manual deviations in tones: "−2 тона", "−полтона", "+1,5 тона".
    private func tones(_ cents: Double) -> String {
        let halfTones = (abs(cents) / 100).rounded()
        let sign = cents < 0 ? "−" : "+"
        if halfTones == 1 { return "\(sign)полтона" }
        if halfTones.truncatingRemainder(dividingBy: 2) == 0 {
            let t = Int(halfTones / 2)
            let word = t % 10 == 1 && t % 100 != 11 ? "тон" : ((2...4).contains(t % 10) && !(12...14).contains(t % 100) ? "тона" : "тонов")
            return "\(sign)\(t) \(word)"
        }
        return "\(sign)\(String(format: "%.1f", halfTones / 2).replacingOccurrences(of: ".", with: ",")) тона"
    }

    private func openSettings() {
        #if os(iOS)
        if tuner.permission == .undetermined {
            Task { await tuner.start(confirmedGap: true) }
            return
        }
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        #else
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}

extension DialCenter {
    var isReference: Bool { if case .reference = self { return true }; return false }
}

/// «Ещё»: three lines with a ring on the top one (canvas icon, 18 pt), the ring filled with the background.
struct MoreIcon: View {
    var body: some View {
        ZStack {
            Icon(.list, size: 18, color: Theme.textBody)
            Circle().fill(Theme.background)
                .overlay(Circle().stroke(Theme.textBody, lineWidth: 1.2))
                .frame(width: 3, height: 3)
                .offset(x: -2.25, y: -3.75)
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

/// String keys in physical order (canvas: 58 pt keys, radius 12, gap 6; the note with its octave inline, 17 pt —
/// medium and ivory when selected; a 14 × 3 status mark 8 pt under it that glows when it is the key's colour).
/// Up to seven in one row, 8–9 in two.
struct StringGrid: View {
    @Environment(AppModel.self) private var app

    static func rows(_ count: Int) -> Int { count > 7 ? 2 : 1 }

    var body: some View {
        let tuner = app.tuner
        let courses = app.tuning.openCents.count
        let dimmed = tuner.permission == .denied || tuner.permission == .restricted || tuner.needsMicrophoneButton || tuner.error != nil
        let columns = Self.rows(courses) > 1 ? (courses + 1) / 2 : courses
        VStack(spacing: 6) {
            ForEach(0..<Self.rows(courses), id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row * columns..<(row * columns + columns), id: \.self) { course in
                        if course < courses { key(course, tuner: tuner) } else { Color.clear.frame(maxWidth: .infinity, maxHeight: 58) }
                    }
                }
            }
        }
        .disabled(dimmed)
    }

    private func key(_ course: Int, tuner: TunerController) -> some View {
        let ref = StringRef(course: course)
        let selected = isSelected(ref, tuner: tuner)
        let color = statusColor(ref, tuner: tuner)
        let spelled = app.tuning.spelledNotes[course]
        return Button {
            tuner.tapString(ref)
        } label: {
            VStack(spacing: 8) {
                Typo.notes(app.formatter.short(spelled.name) + "\(spelled.octave)", size: 17, weight: selected ? .medium : .regular)
                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textMuted)
                    .lineLimit(1).minimumScaleFactor(0.6)
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 14, height: 3)
                    .shadow(color: selected && color != Theme.neutralMark ? color : .clear, radius: 3)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? Theme.keyFillSelected : Theme.keyFill))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? Theme.selectedBorder : Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Струна \(app.stringName(ref))")
        .accessibilityValue(accessibilityStatus(ref, tuner: tuner))
    }

    private func isSelected(_ ref: StringRef, tuner: TunerController) -> Bool {
        #if DEBUG
        if let demo = TunerDemo.current {
            guard let label = demo.selected else { return false }
            let spelled = app.tuning.spelledNotes[ref.course]
            return app.formatter.short(spelled.name) + "\(spelled.octave)" == label
        }
        #endif
        if case .manual(let m) = tuner.mode { return m.course == ref.course }
        if tuner.isReferencePlaying, let r = tuner.referenceString { return r.course == ref.course }
        if case .reading(let r) = tuner.display, case let .string(current, _, _) = r.target { return current.course == ref.course }
        return tuner.mode == .auto && tuner.lastString?.course == ref.course
    }

    private func statusColor(_ ref: StringRef, tuner: TunerController) -> Color {
        let status: TunerController.StringStatus
        #if DEBUG
        if let demo = TunerDemo.current {
            status = isSelected(ref, tuner: tuner) ? demo.selectedMark : (demo.marks(app.tuning.openCents.count)[ref.course] ?? .unknown)
            return Self.color(status)
        }
        #endif
        status = tuner.stringStatus[ref] ?? (tuner.tuned.contains(ref) ? .inTune : .unknown)
        return Self.color(status)
    }

    static func color(_ status: TunerController.StringStatus) -> Color {
        switch status {
        case .inTune: return Theme.inTune
        case .flat: return Theme.flat
        case .sharp: return Theme.sharp
        case .unknown: return Theme.neutralMark
        }
    }

    private func accessibilityStatus(_ ref: StringRef, tuner: TunerController) -> String {
        switch tuner.stringStatus[ref] ?? .unknown {
        case .inTune: return "в строю"
        case .flat: return "ниже"
        case .sharp: return "выше"
        case .unknown: return ""
        }
    }
}

/// Chromatic mode (canvas «Тюнер — хроматический»): instead of the strings, nine note names around the one heard —
/// 26 pt columns spread over the row, bottoms on one line; the heard note 22 semibold ivory, the others 13 tertiary.
struct ChromaticStrip: View {
    @Environment(AppModel.self) private var app
    let current: Int
    let highlighted: Bool

    var body: some View {
        let flats = app.tuning.spelledNotes.contains { $0.name.accidental < 0 }
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(-4...4, id: \.self) { offset in
                let pc = ((current + offset) % 12 + 12) % 12
                let name = app.formatter.string(NoteName.simpleSpelling(ofPitchClass: pc, preferFlats: flats))
                let big = offset == 0 && highlighted
                Typo.notes(name, size: big ? 22 : 13, weight: big ? .semibold : .regular)
                    .foregroundStyle(big ? Theme.textPrimary : Theme.textTertiary)
                    .lineLimit(1).fixedSize()
                    .frame(width: 26)
                if offset < 4 { Spacer(minLength: 0) }
            }
        }
        .frame(height: 58, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Хроматический режим")
    }
}

/// Large-text strings (canvas «Тюнер — крупный шрифт»): three in a row, 74 pt, radius 14, 28 semibold with a
/// 16 pt tertiary octave inline, a 20 × 4 status mark 8 pt under it.
struct LargeStringGrid: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let tuner = app.tuner
        let courses = app.tuning.openCents.count
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(0..<courses, id: \.self) { course in
                let ref = StringRef(course: course)
                let selected: Bool = {
                    #if DEBUG
                    if let demo = TunerDemo.current {
                        let s = app.tuning.spelledNotes[course]
                        return demo.selected == app.formatter.short(s.name) + "\(s.octave)"
                    }
                    #endif
                    if case .manual(let m) = tuner.mode { return m.course == course }
                    if case .reading(let r) = tuner.display, case let .string(current, _, _) = r.target { return current.course == course }
                    return false
                }()
                let spelled = app.tuning.spelledNotes[course]
                Button { tuner.tapString(ref) } label: {
                    VStack(spacing: 8) {
                        (Typo.notes(app.formatter.short(spelled.name), size: 28, weight: .semibold, fixed: true).foregroundColor(Theme.textPrimary)
                            + Text("\(spelled.octave)").font(Typo.fixed(16)).foregroundColor(Theme.textTertiary))
                            .lineLimit(1)
                        RoundedRectangle(cornerRadius: 2).fill(color(ref, selected: selected, tuner: tuner)).frame(width: 20, height: 4)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 74)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(selected ? 0.09 : 0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? Theme.selectedBorder : Theme.hairline, lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Струна \(app.stringName(ref))")
            }
        }
    }

    private func color(_ ref: StringRef, selected: Bool, tuner: TunerController) -> Color {
        #if DEBUG
        if let demo = TunerDemo.current {
            return StringGrid.color(selected ? demo.selectedMark : (demo.marks(app.tuning.openCents.count)[ref.course] ?? .unknown))
        }
        #endif
        return StringGrid.color(tuner.stringStatus[ref] ?? (tuner.tuned.contains(ref) ? .inTune : .unknown))
    }
}

/// Large-text mode segments (canvas): 46 pt segments, radius 23, padding 3 + 1 pt border (radius 26), 19 semibold.
struct LargeSegments: View {
    @Binding var selection: TunerController.Choice

    var body: some View {
        HStack(spacing: 0) {
            ForEach([(TunerController.Choice.auto, "Авто"), (.manual, "Ручной"), (.chromatic, "Хром.")], id: \.0) { value, title in
                let selected = value == selection
                Button { withAnimation(Motion.out(Motion.Duration.quick)) { selection = value } } label: {
                    Text(title).font(Typo.fixed(19, .semibold))
                        .foregroundStyle(selected ? Theme.background : Theme.textSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Capsule(style: .circular).fill(selected ? Theme.accent : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 26).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

/// Route notices over the tuner (canvas «Тюнер — Bluetooth», «Интерфейс отключён» — an orange-bordered card under
/// the header; «Вход переключён» — a centred toast).
struct TunerNoticeView: View {
    let notice: TunerController.RouteNotice
    let dismiss: () -> Void
    let speaker: () -> Void

    var body: some View {
        switch notice {
        case let .bluetooth(name, latency):
            card(icon: .bluetooth, title: "\(name): задержка ~\(latency) мс",
                 text: "Для тюнера это неважно, но эталонный тон и метроном будут опаздывать. Слушаем микрофон телефона.", spacing: 8) {
                HStack(spacing: 8) {
                    Button(action: dismiss) {
                        Text("Понятно").font(Typo.button).foregroundStyle(Theme.background)
                            .padding(.horizontal, 18).frame(height: 36)
                            .background(Capsule(style: .circular).fill(Theme.primaryFill))
                    }
                    .buttonStyle(PressableStyle())
                    Button { speaker(); dismiss() } label: {
                        Text("Звук в динамик").font(Typo.inter(15, .medium)).foregroundStyle(Theme.textBody)
                            .padding(.horizontal, 18).frame(height: 36)
                            .background(Capsule(style: .circular).fill(Theme.cardFill))
                            .overlay(Capsule(style: .circular).strokeBorder(Theme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        case let .disconnected(name):
            card(icon: .audioInterface, title: "Интерфейс отключён",
                 text: "\(name) пропал. Слушаю микрофон телефона — вернёмся к интерфейсу, когда подключите.", spacing: 4) { EmptyView() }
                .onTapGesture(perform: dismiss)
        case let .inputSwitched(text):
            HStack(spacing: 10) {
                Icon(.audioInterface, size: 16, color: Theme.textSecondary)
                Text(text).font(Typo.inter(13, .medium)).foregroundStyle(Theme.textBody).lineLimit(1)
            }
            .padding(.horizontal, 17).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(red: 38 / 255, green: 40 / 255, blue: 45 / 255, opacity: 0.96)))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairlineStrong, lineWidth: 1))
            .shadow(color: .black.opacity(0.6), radius: 15, y: 14)
            .padding(.horizontal, 24)
            .onTapGesture(perform: dismiss)
        }
    }

    /// Padding 12 / 14 + 1 pt border, radius 14, #1e1f23 at 98 %, orange 40 % border, 20 pt icon 10 pt from the text.
    private func card(icon: AppIcon, title: String, text: String, spacing: CGFloat, @ViewBuilder actions: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Icon(icon, size: 20, color: Theme.sharp)
            VStack(alignment: .leading, spacing: spacing) {
                Text(title).font(Typo.inter(14, .semibold)).foregroundStyle(Theme.textPrimary)
                // line-height 1.4 on 12 pt: 16.8 pt lines (Inter's own 14.5).
                Text(text).font(Typo.caption).foregroundStyle(Theme.textSecondary)
                    .lineSpacing(2.27).padding(.vertical, 1.13)
                    .fixedSize(horizontal: false, vertical: true)
                actions()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 15).padding(.vertical, 13)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 30 / 255, green: 31 / 255, blue: 35 / 255, opacity: 0.98)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.sharp.opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.6), radius: 15, y: 14)
        .padding(.horizontal, 20)
    }
}

/// «Ещё» (canvas «Тюнер — дополнительно», FixTunerPro): noise gate, target, strobe switch, stage, intonation check,
/// A4 of this tuning.
struct TunerProSheet: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let tuner = app.tuner
        // Measured on the render: the canvas cards keep their 1 pt border inside the padding (as `Card` does); the rows
        // are 60 / 52 plus their own 1 pt bottom border.
        DesignSheet(title: "Тюнер · дополнительно", height: 618, close: { app.sheet = nil }) {
            VStack(alignment: .leading, spacing: 14) {
                Card {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top) {
                            Text("Порог шума").font(Typo.row).foregroundStyle(Theme.textBody)
                            Spacer()
                            Text("\(signedInt(tuner.noiseGate)) дБ").font(Typo.inter(14)).foregroundStyle(Theme.textSecondary)
                        }
                        Text("выше — не реагирует на гул комнаты").font(Typo.caption).foregroundStyle(Theme.textTertiary)
                            .padding(.top, 2)
                        GateSlider(value: Binding(get: { tuner.noiseGate }, set: { tuner.noiseGate = $0 }), range: TunerController.noiseGateRange)
                            .padding(.top, 10)
                    }
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 15)
                }
                VStack(alignment: .leading, spacing: 0) {
                    SectionCaption(text: "Цель")
                    Card {
                        SegmentedPill(options: [(TunerController.Choice.auto, "Струны строя"), (.chromatic, "Ближайшая ступень")],
                                      selection: Binding(get: { tuner.choice == .chromatic ? .chromatic : .auto }, set: { tuner.choice = $0 }))
                            .padding(6)
                    }
                }
                Card {
                    VStack(spacing: 0) {
                        CardRow(title: "Строб", subtitle: "вращение — точная подстройка", minHeight: 61) {
                            ToggleSwitch(isOn: Binding(get: { tuner.strobeView }, set: { tuner.strobeView = $0 }), label: "Строб")
                        }
                        Button { app.sheet = nil; tuner.showStage = true } label: {
                            CardRow(title: "Сценический режим", subtitle: "нота и цвет на весь экран", minHeight: 61) {
                                Icon(.chevronRight, size: 16, color: Theme.textTertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        Button { app.sheet = .intonation } label: {
                            CardRow(title: "Проверка мензуры", subtitle: "открытая против 12-го лада", minHeight: 61) {
                                Icon(.chevronRight, size: 16, color: Theme.textTertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        Button { app.tuningEditorFromTuner = true; app.sheet = .tuningEditor(app.tuning.id) } label: {
                            CardRow(title: "Частота (A4) этого строя", minHeight: 53) {
                                HStack(spacing: 8) {
                                    Text("\(Int(app.a4)) Гц")
                                    Icon(.chevronRight, size: 16, color: Theme.textTertiary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func signedInt(_ v: Double) -> String {
        let i = Int(v.rounded())
        return i < 0 ? "−\(-i)" : "\(i)"
    }
}

/// Canvas slider: a 4 pt track (white 12 %) with the ivory part up to the value, a 28 pt white knob; 28 pt high.
struct GateSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let p = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            ZStack(alignment: .topLeading) {
                Capsule().fill(Color.white.opacity(0.12)).frame(width: w, height: 4).offset(y: 12)
                Capsule().fill(Theme.accent).frame(width: w * p, height: 4).offset(y: 12)
                Circle().fill(Color.white).frame(width: 28, height: 28)
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
                    .offset(x: w * p - 14)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let f = max(0, min(1, g.location.x / max(1, w)))
                value = (range.lowerBound + f * (range.upperBound - range.lowerBound)).rounded()
            })
        }
        .frame(height: 28)
        .accessibilityElement()
        .accessibilityLabel("Порог шума")
        .accessibilityValue("\(Int(value)) дБ")
        .accessibilityAdjustableAction { d in
            value = max(range.lowerBound, min(range.upperBound, value + (d == .increment ? 1 : -1)))
        }
    }
}

#if DEBUG
/// Screenshot hook: `-tunerDemo <state>` freezes the screen on a state of the canvas (the simulator hears no
/// guitar; every animation stands at its first frame). States — the boards FixTunerFlat / Sharp / Waiting / Done /
/// Reference / OutOfRange / NoAccess, TunerListening / Manual / Chromatic / Strobe / Bluetooth / EngineFail /
/// InputSwitched, DeviceDisconnected, TunerStagePhone (`-tunerStage`). The selected key is named by its label
/// («A2»), the marks count from the lowest string — so the same state works on 6, 7 and 8 strings (S6/S7/S8Tuner).
struct TunerDemo {
    struct Action { let title: String; let width: CGFloat }
    var center: DialCenter
    var status: (text: String, color: Color)
    var cents: Double?
    var color: Color?
    var inTune = false
    var selected: String?
    /// Marks of the lowest strings (index 0 = the lowest) and of the selected one.
    var lowMarks: [TunerController.StringStatus] = []
    var selectedMark: TunerController.StringStatus = .unknown
    var allMarks: TunerController.StringStatus?
    var choice: TunerController.Choice = .auto
    var strobe = false
    var done = false
    var action: Action?
    var notice: TunerController.RouteNotice?
    var input: String?
    var chromaticPitchClass: Int?
    /// Where the canvas render catches the spinning band (0.05 s in: «spinrev 6s» −3°, «spin 1.2s» +15°, «spin 6s» +3°).
    var bandAngle: Double = 0

    @MainActor func marks(_ count: Int) -> [Int: TunerController.StringStatus] {
        var result: [Int: TunerController.StringStatus] = [:]
        if let allMarks { for c in 0..<count { result[c] = allMarks }; return result }
        for (i, m) in lowMarks.enumerated() { result[i] = m }
        return result
    }

    private static func note(_ name: String, _ octave: String, _ cents: String, _ color: Color, _ detail: String, dimmed: Bool = false) -> DialCenter {
        .note(name: name, octave: octave, cents: cents, centsColor: color, detail: detail, dimmed: dimmed)
    }

    private static let flat = TunerDemo(center: note("A", "2", "−14 ц", Theme.flat, "109,1 Гц · цель 110,0"),
                                        status: ("Ниже — подтяните", Theme.flat), cents: -14, color: Theme.flat,
                                        selected: "A2", lowMarks: [.inTune], selectedMark: .flat, bandAngle: -3)

    static let current: TunerDemo? = {
        switch UserDefaults.standard.string(forKey: "tunerDemo") {
        case "flat":
            return flat
        case "large":
            // Canvas «Тюнер — крупный шрифт»: the flat reading, no string marked yet.
            var d = flat
            d.lowMarks = []
            return d
        case "sharp":
            return TunerDemo(center: note("D", "3", "+31 ц", Theme.sharp, "148,5 Гц · цель 146,8"),
                             status: ("Выше — ослабьте", Theme.sharp), cents: 31, color: Theme.sharp, selected: "D3", lowMarks: [.inTune, .inTune], selectedMark: .sharp, bandAngle: 15)
        case "waiting":
            return TunerDemo(center: note("E", "2", "", Theme.inTune, "начните с 6-й струны", dimmed: true),
                             status: ("Сыграйте струну", Theme.textBody))
        case "done":
            return TunerDemo(center: .done(detail: "6 из 6 струн в строю"), status: ("Все струны в строю", Theme.inTune),
                             color: Theme.inTune, inTune: true, allMarks: .inTune, done: true)
        case "reference":
            return TunerDemo(center: .reference(title: "Эталон E2", detail: "82,41 Гц · анализ на паузе"),
                             status: ("Звучит эталон · 3 с", Theme.textBody), selected: "E2")
        case "outOfRange":
            return TunerDemo(center: .message(icon: .warning, iconColor: Theme.textBody, title: "Вне диапазона",
                                              detail: "Ниже 25 Гц или выше последнего лада"),
                             status: ("Сыграйте открытую струну", Theme.textBody), lowMarks: [.inTune])
        case "noAccess":
            return TunerDemo(center: .message(icon: .micOff, iconColor: Theme.sharp, title: "Нужен микрофон",
                                              detail: "Тюнер слышит струну. Звук не записывается"),
                             status: ("", Theme.textBody), action: Action(title: "Разрешить микрофон", width: 250))
        case "engineFail":
            return TunerDemo(center: .message(icon: .warning, iconColor: Theme.sharp, title: "Звук недоступен",
                                              detail: "Микрофон занят другим приложением или звонком"),
                             status: ("", Theme.textBody), action: Action(title: "Повторить", width: 200))
        case "listening":
            return TunerDemo(center: .listening, status: ("Дайте струне прозвучать", Theme.textBody))
        case "manual":
            return TunerDemo(center: note("G", "3", "−3 ц", Theme.inTune, "195,6 Гц · цель 196,0"),
                             status: ("Ручной: только G3 — другие ноты не мешают", Theme.inTune), cents: -3, color: Theme.inTune,
                             inTune: true, selected: "G3", lowMarks: [.inTune, .inTune, .inTune], selectedMark: .inTune, choice: .manual, bandAngle: -3)
        case "chromatic":
            return TunerDemo(center: note("C♯", "4", "+6 ц", Theme.inTune, "279,2 Гц"),
                             status: ("Хроматический: любая нота, не только струны строя", Theme.textBody), cents: 6, color: Theme.inTune,
                             inTune: true, choice: .chromatic, chromaticPitchClass: 1, bandAngle: 3)
        case "strobe":
            return TunerDemo(center: .strobeNote(name: "A", octave: "2", line: "−2 ц · полосы почти стоят", color: Theme.inTune),
                             status: ("", Theme.textBody), cents: -2, color: Theme.inTune, inTune: true, selected: "A2",
                             lowMarks: [.inTune], strobe: true)
        case "stage":
            return TunerDemo(center: note("E", "2", "+1 ц", Theme.inTune, ""), status: ("В строю", Theme.inTune),
                             cents: 1, color: Theme.inTune, inTune: true, selected: "E2")
        case "bluetooth":
            var d = flat
            d.status.color = Theme.textBody
            d.lowMarks = []
            d.notice = .bluetooth(name: "AirPods", latency: 180)
            d.bandAngle = 0
            return d
        case "disconnected":
            var d = flat
            d.status.color = Theme.textBody
            d.lowMarks = []
            d.notice = .disconnected(name: "Focusrite 2i2")
            d.bandAngle = 0
            return d
        case "inputSwitched":
            var d = flat
            d.notice = .inputSwitched(text: "Слушаю Focusrite 2i2 · вход 1 (гитара)")
            d.input = "Focusrite 2i2"
            return d
        case "landscape":
            return TunerDemo(center: note("D", "3", "+31 ц", Theme.sharp, "148,5 Гц · цель 146,8"),
                             status: ("Выше — ослабьте", Theme.sharp), cents: 31, color: Theme.sharp, selected: "D3", lowMarks: [.inTune, .inTune], selectedMark: .sharp, bandAngle: 15)
        default:
            return nil
        }
    }()
}
#endif

/// The dial as one adjustable VoiceOver element: «Тюнер. A2, ниже на 14 центов». Spoken updates — at most once per
/// 1.5 s and only when the reading moved by more than 3 c; «В строю» at once (canvas «Тюнер — VoiceOver»).
struct TunerVoiceOver: ViewModifier {
    let value: String
    let inTune: Bool
    let cents: Double?
    let adjust: (Bool) -> Void
    @State private var lastSpoken = Date.distantPast
    @State private var lastCents: Double?
    @State private var lastInTune = false

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Тюнер")
            .accessibilityValue(value)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: adjust(true)
                case .decrement: adjust(false)
                @unknown default: break
                }
            }
            .onChange(of: value) { _, newValue in announce(newValue) }
    }

    private func announce(_ text: String) {
        #if os(iOS)
        guard UIAccessibility.isVoiceOverRunning else { return }
        #endif
        if inTune && !lastInTune {
            lastInTune = true
            lastSpoken = Date()
            AccessibilityNotification.Announcement("В строю").post()
            return
        }
        lastInTune = inTune
        guard Date().timeIntervalSince(lastSpoken) >= 1.5 else { return }
        if let c = cents, let last = lastCents, abs(c - last) <= 3 { return }
        lastSpoken = Date()
        lastCents = cents
        AccessibilityNotification.Announcement(text).post()
    }
}

/// TU-12 (canvas «Тюнер — сцена», TunerStagePhone): the deviation colour as a radial glow over the whole screen,
/// the tuning and «касание — выйти» at the top (70), the note 220 ExtraLight with a 56 pt octave (190), «В строю ·
/// +1 ц» 34 medium (470), a ±50 c line 310 wide with a 4 × 28 marker (560), «Экран не гаснет · яркость на максимум»
/// (700). A tap anywhere leaves. «Затемнение вспышек» and Reduce Motion: muted colours and a slow cross-fade.
struct TunerStageView: View {
    let center: DialCenter
    let cents: Double?
    let inTune: Bool
    let tuningName: String
    let close: () -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(iOS)
    @State private var brightness: CGFloat?
    #endif

    private var dimFlashing: Bool {
        #if os(iOS)
        return MADimFlashingLightsEnabled()
        #else
        return false
        #endif
    }

    private var hasReading: Bool { cents != nil }

    /// The canvas glow (in tune): rgba(70,224,143,0.32) → rgba(10,40,26,0.9) at 70 % → #06130c; the same recipe
    /// in blue / orange for flat / sharp.
    private var glow: [Color] {
        guard let cents, !dimFlashing else { return [.clear, .clear, .clear] }
        if inTune || abs(cents) <= 3 {
            return [Color(red: 70 / 255, green: 224 / 255, blue: 143 / 255, opacity: 0.32), Color(red: 10 / 255, green: 40 / 255, blue: 26 / 255, opacity: 0.9), Color(hex: 0x06130c)]
        }
        if cents < 0 {
            return [Color(red: 106 / 255, green: 168 / 255, blue: 255 / 255, opacity: 0.32), Color(red: 10 / 255, green: 24 / 255, blue: 46 / 255, opacity: 0.9), Color(hex: 0x060b14)]
        }
        return [Color(red: 255 / 255, green: 155 / 255, blue: 82 / 255, opacity: 0.32), Color(red: 46 / 255, green: 24 / 255, blue: 10 / 255, opacity: 0.9), Color(hex: 0x140b06)]
    }

    /// «В строю · +1 ц» — a pale tint of the deviation colour.
    private var lineColor: Color {
        guard let cents else { return Theme.textSecondary }
        if inTune || abs(cents) <= 3 { return Color(hex: 0xb9f5d4) }
        return cents < 0 ? Color(hex: 0xc9defd) : Color(hex: 0xffd9bd)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            // Board rows at 844 pt; taller or shorter screens stretch them.
            let k = geo.size.height / 844
            ZStack(alignment: .topLeading) {
                Theme.screenBackground
                // radial-gradient(80% 60% at 50% 40%): radii 0.8 w × 0.6 h around (0.5 w, 0.4 h).
                EllipticalGradient(stops: [.init(color: glow[0], location: 0), .init(color: glow[1], location: 0.7), .init(color: glow[2], location: 1)],
                                   center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
                    .frame(width: 1.6 * w, height: 1.2 * geo.size.height)
                    .position(x: 0.5 * w, y: 0.4 * geo.size.height)
                    .opacity(hasReading ? 1 : 0)
                HStack {
                    Text(tuningName).font(Typo.inter(13)).foregroundStyle(Color.white.opacity(0.6))
                    Spacer()
                    Text("касание — выйти").font(Typo.inter(13)).foregroundStyle(Color.white.opacity(0.6))
                }
                .padding(.horizontal, 20)
                .frame(width: w)
                .offset(y: 70 * k)
                noteText
                    .frame(width: w, height: 220)
                    .offset(y: 190 * k)
                Text(centsLine).font(Typo.inter(34, .medium)).foregroundStyle(lineColor)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .frame(width: w)
                    .offset(y: 470 * k)
                marker(width: min(w - 80, 520))
                    .frame(width: w)
                    .offset(y: 560 * k)
                Text("Экран не гаснет · яркость на максимум").font(Typo.inter(13)).foregroundStyle(Color.white.opacity(0.55))
                    .frame(width: w)
                    .offset(y: 700 * k)
            }
            .frame(width: w, height: geo.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture(perform: close)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: dimFlashing || reduceMotion ? 0.6 : 0.15), value: lineColor)
        .monospacedDigit()
        #if os(iOS)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            #if DEBUG
            if TunerDemo.current != nil { return }
            #endif
            brightness = UIScreen.main.brightness
            UIScreen.main.brightness = 1
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            if let brightness { UIScreen.main.brightness = brightness }
        }
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Закрыть сценический режим", close)
    }

    /// The note 220 pt ExtraLight, line-height 1, the octave an inline 56 pt span at 70 %.
    @ViewBuilder private var noteText: some View {
        switch center {
        case let .note(name, octave, _, _, _, _), let .strobeNote(name, octave, _, _):
            (Typo.notes(name, size: 220, weight: .extraLight, fixed: true).foregroundColor(.white)
                + Text(octave).font(Typo.fixed(56)).foregroundColor(Color.white.opacity(0.7)))
                .lineLimit(1).minimumScaleFactor(0.4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .opacity(hasReading ? 1 : 0.3)
                .accessibilityLabel(name + octave)
        case .done:
            Icon(.check, size: 132, lineWidth: 6, color: Theme.inTune).frame(maxWidth: .infinity)
        default:
            Text("Сыграйте струну").font(Typo.inter(26, .medium))
                .foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity)
        }
    }

    private var centsLine: String {
        guard let cents else { return "" }
        let v = Int(cents.rounded())
        let c = (v > 0 ? "+\(v)" : v < 0 ? "−\(-v)" : "0") + " ц"
        if inTune || abs(cents) <= 3 { return "В строю · " + c }
        return c + " · " + (v < 0 ? "подтяните" : "ослабьте")
    }

    /// ±50 c line (12 pt, white 15 %) with a 4 × 28 white marker, 2 pt per cent from the centre.
    private func marker(width: CGFloat) -> some View {
        let x = CGFloat(max(-50, min(50, cents ?? 0))) * 2 + 2
        return ZStack(alignment: .topLeading) {
            Capsule().fill(Color.white.opacity(0.15)).frame(width: width, height: 12)
            RoundedRectangle(cornerRadius: 2).fill(Color.white).frame(width: 4, height: 28)
                .offset(x: width / 2 + x, y: -8)
                .opacity(hasReading ? 1 : 0)
        }
        .frame(width: width, height: 12, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}
