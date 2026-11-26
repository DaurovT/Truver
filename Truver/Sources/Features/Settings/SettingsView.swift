import SwiftUI
import TruverTheory
#if os(iOS)
import AVFoundation
#endif

/// Settings by the corrected canvas («Настройки», «Частота настройки (A4)», «Вход», «Громкость и задержка»,
/// «Обозначение нот», «Выход звука», «крупный шрифт»): a full screen with a pinned header and pages. Metronome sounds,
/// flash and the session timer open the metronome's sheets.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var path: [SettingsPage] = []

    enum SettingsPage: Hashable { case noise, target, notation, a4, input, output, volume, about, help }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if typeSize.isAccessibilitySize {
                    SettingsPageFrame(title: "Настройки", style: .large, back: { app.showSettings = false }) { largeMain }
                } else {
                    SettingsPageFrame(title: "Настройки", fade: true, back: { app.showSettings = false }) { main }
                }
            }
            .navigationDestination(for: SettingsPage.self) { page in
                switch page {
                case .noise: SettingsPageFrame(title: "Порог шума", back: pop) { NoiseGatePage() }
                case .target: SettingsPageFrame(title: "Цель", back: pop) { TargetPage() }
                case .notation: SettingsPageFrame(title: "Обозначение нот", back: pop) { NotationPage() }
                case .a4: SettingsPageFrame(title: "Частота настройки (A4)", back: pop) { A4Page() }
                case .input: SettingsPageFrame(title: "Вход", back: pop) { InputPage(openNoise: { path.append(.noise) }) }
                case .output: SettingsPageFrame(title: "Выход звука", back: pop) { OutputPage(openCheck: { path.append(.volume) }) }
                case .volume: SettingsPageFrame(title: "Громкость и задержка", back: pop) { VolumePage() }
                case .about: AboutView(back: pop)
                case .help: HelpSettingsPage(back: pop)   // «Обучение» (Features/Tour)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Screenshot hook: `-settingsPage noise|target|notation|a4|input|output|volume|about`.
            switch UserDefaults.standard.string(forKey: "settingsPage") {
            case "noise"?: path = [.noise]
            case "target"?: path = [.target]
            case "notation"?: path = [.notation]
            case "a4"?: path = [.a4]
            case "input"?: path = [.input]
            case "output"?: path = [.output]
            case "volume"?: path = [.volume]
            case "about"?, "thanks"?: path = [.about]   // «thanks»: AboutView opens «Спасибо» itself
            case "help"?: path = [.help]
            default: break
            }
        }
    }

    private func pop() { if !path.isEmpty { path.removeLast() } }

    private func row(_ title: String, _ value: String? = nil, last: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CardRow(title: title, showsDivider: !last, minHeight: 51) {
                HStack(spacing: 8) {
                    if let value { Typo.notes(value, size: 14) }
                    Icon(.chevronRight, size: 16, color: Theme.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Values

    static func notationValue(_ notation: NoteNotation) -> String {
        switch notation {
        case .international: return "C D E … B"
        case .german: return "C D E … H"
        case .solfege: return "До Ре Ми …"
        }
    }

    private var flashValue: String {
        switch app.settings.metronome.flash {
        case .off: return "Выкл"
        case .strip: return "Полоса долей"
        case .screen: return "Весь экран"
        }
    }

    private var timerValue: String {
        let m = app.settings.metronome
        return m.timerEnabled ? "\(m.timerMinutes) мин" : "выкл"
    }

    private var targetValue: String { app.tuner.choice == .chromatic ? "Ближайшая ступень" : "Струны строя" }
    private var noiseValue: String { SettingsFormat.decibels(app.tuner.noiseGate) }

    private var inputValue: String {
        #if os(iOS)
        return app.audio.session.currentInputName ?? "Микрофон"
        #else
        return "Микрофон"
        #endif
    }

    private var outputValue: String {
        #if os(iOS)
        return app.audio.session.currentOutputName ?? "Динамик"
        #else
        return "Выход"
        #endif
    }

    // MARK: Main

    private var main: some View {
        VStack(spacing: 14) {
            VStack(spacing: 0) {
                SectionCaption(text: "Тюнер и ноты")
                Card {
                    row("Порог шума", noiseValue) { path.append(.noise) }
                    row("Цель", targetValue) { path.append(.target) }
                    row("Частота настройки (A4)", "\(Int(app.settings.defaultA4)) Гц") { path.append(.a4) }
                    row("Обозначение нот", Self.notationValue(app.settings.notation), last: true) { path.append(.notation) }
                }
            }
            VStack(spacing: 0) {
                SectionCaption(text: "Звук")
                Card {
                    row("Вход", inputValue) { path.append(.input) }
                    row("Выход", outputValue) { path.append(.output) }
                    row("Громкость и задержка", last: true) { path.append(.volume) }
                }
            }
            VStack(spacing: 0) {
                SectionCaption(text: "Метроном")
                Card {
                    row("Звуки", SoundsSheet.title(app.settings.metronome.sound)) { openSheet(.metroSounds) }
                    #if os(iOS)
                    CardRow(title: "Вибрация", minHeight: 51) {
                        ToggleSwitch(isOn: Binding(get: { app.settings.vibration }, set: { app.settings.vibration = $0 }), label: "Вибрация")
                    }
                    #endif
                    row("Вспышка", flashValue) { openSheet(.metroSounds) }
                    row("Таймер занятия", timerValue, last: true) { openSheet(.metroTimer) }
                }
            }
            VStack(spacing: 0) {
                SectionCaption(text: "О приложении")
                Card {
                    row("О Truver", "версия \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")") { path.append(.about) }
                    row("Обучение") { path.append(.help) }
                    row("Обратная связь", last: true) {
                        if let url = URL(string: "mailto:?subject=Truver") { openURL(url) }
                    }
                }
            }
        }
    }

    // MARK: Large text («Настройки — крупный шрифт (значение под названием)»)

    private func largeRow(_ title: String, _ value: String? = nil, last: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Typo.fixed(22)).foregroundStyle(Theme.textPrimary)
                if let value { Typo.notes(value, size: 19, fixed: true).foregroundStyle(Theme.textSecondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 15)
            .overlay(alignment: .bottom) { if !last { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func largeSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        let rows = content()
        return VStack(spacing: 0) {
            // The caption keeps its 12 pt on the board.
            Text(title).font(Typo.fixed(12)).foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 4).padding(.bottom, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            Card { rows }
        }
    }

    /// The board lists fewer rows than the regular page: no «Цель» (the tuner's own segments set it) and no
    /// «Громкость и задержка» (reachable from «Выход → Проверить на слух»).
    private var largeMain: some View {
        VStack(spacing: 14) {
            largeSection("Тюнер и ноты") {
                largeRow("Порог шума", noiseValue) { path.append(.noise) }
                largeRow("Частота настройки (A4)", "\(Int(app.settings.defaultA4)) Гц") { path.append(.a4) }
                largeRow("Обозначение нот", Self.notationValue(app.settings.notation), last: true) { path.append(.notation) }
            }
            largeSection("Звук") {
                largeRow("Вход", inputValue) { path.append(.input) }
                // The board keeps only the two device rows; «Громкость и задержка» stays reachable from «Выход».
                largeRow("Выход", outputValue, last: true) { path.append(.output) }
            }
            largeSection("Метроном") {
                largeRow("Звуки", SoundsSheet.title(app.settings.metronome.sound)) { openSheet(.metroSounds) }
                #if os(iOS)
                HStack {
                    Text("Вибрация").font(Typo.fixed(22)).foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 8)
                    ToggleSwitch(isOn: Binding(get: { app.settings.vibration }, set: { app.settings.vibration = $0 }), label: "Вибрация")
                }
                .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 15)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
                #endif
                largeRow("Вспышка", flashValue) { openSheet(.metroSounds) }
                largeRow("Таймер занятия", timerValue, last: true) { openSheet(.metroTimer) }
            }
            largeSection("О приложении") {
                largeRow("О Truver", "версия \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")") { path.append(.about) }
                largeRow("Обучение") { path.append(.help) }
                largeRow("Обратная связь", last: true) {
                    if let url = URL(string: "mailto:?subject=Truver") { openURL(url) }
                }
            }
        }
    }

    private func openSheet(_ sheet: AppSheet) {
        app.showSettings = false
        app.sheet = sheet
    }
}

enum SettingsFormat {
    /// «−55 дБ» with a typographic minus (canvas).
    static func decibels(_ value: Double) -> String {
        let v = Int(value.rounded())
        return (v < 0 ? "−\(-v)" : "\(v)") + " дБ"
    }
}

/// Page frame of the corrected canvas: back button 40 + title 17 medium (gap 12) in a 44 pt row 50 pt from the top,
/// a hairline under the pinned header (102), content from 116 in a scroll view with 20 pt margins. `.large` — the
/// large-text board: a 34 pt bold title instead of the back button and no hairline (a round close button stays on the
/// right, so the cover can still be closed).
struct SettingsPageFrame<Content: View>: View {
    enum Style { case regular, large }
    let title: String
    var style: Style = .regular
    /// The main page fades its scrolled content out at the bottom (canvas: 54 pt from 790 down to #0d0e10).
    var fade = false
    let back: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            ScreenBackground()
            VStack(spacing: 0) {
                if style == .large {
                    HStack(alignment: .center, spacing: 12) {
                        Text(title).font(Typo.fixed(34, .bold)).foregroundStyle(Theme.textPrimary).accessibilityAddTraits(.isHeader)
                        Spacer()
                        RoundIconButton(icon: .close, iconSize: 16, label: "Закрыть", action: back)
                    }
                    .frame(height: 44).padding(.horizontal, 20).padding(.top, 3)
                    .padding(.bottom, 9)
                } else {
                    HStack(spacing: 12) {
                        RoundIconButton(icon: .chevronLeft, label: "Назад", action: back)
                        Text(title).font(Typo.inter(17, .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1).accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 0)
                    }
                    .frame(height: 44).padding(.horizontal, 20).padding(.top, 3)
                    .padding(.bottom, 8)
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                }
                ScrollView {
                    content().padding(.horizontal, 20).padding(.top, 13).padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            if fade {
                VStack {
                    Spacer()
                    LinearGradient(colors: [Color(hex: 0x0d0e10, opacity: 0), Color(hex: 0x0d0e10)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 54)
                }
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
            }
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .navigationBarBackButtonHidden()
    }
}

/// A row with a check mark on the right (canvas lists of devices and notations): title 15, optional subtitle 12.
/// `dimmed` — a device that is not connected (title tertiary).
struct CheckRow: View {
    let title: String
    var subtitle: String?
    var selected = false
    var dimmed = false
    var titleColor: Color?
    var minHeight: CGFloat = 53
    var showsDivider = true
    var action: (() -> Void)?

    var body: some View {
        let row = HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typo.row).foregroundStyle(titleColor ?? (dimmed ? Theme.textTertiary : Theme.textBody))
                if let subtitle { Text(subtitle).font(Typo.caption).foregroundStyle(Theme.textTertiary) }
            }
            Spacer(minLength: 8)
            if selected { Icon(.check, size: 20, lineWidth: 2, color: Theme.textPrimary) }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: minHeight)
        .overlay(alignment: .bottom) { if showsDivider { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) } }
        .contentShape(Rectangle())
        if let action {
            Button(action: action) { row }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            row.accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Tuner and notes

/// «Порог шума» (not drawn on the canvas; the same control as the tuner's pro panel): the level below which the tuner
/// ignores the room.
struct NoiseGatePage: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let tuner = app.tuner
        VStack(alignment: .leading, spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Порог шума").font(Typo.row).foregroundStyle(Theme.textBody)
                        Spacer()
                        Text(SettingsFormat.decibels(tuner.noiseGate)).font(Typo.inter(14)).foregroundStyle(Theme.textSecondary)
                    }
                    VolumeSlider(value: Binding(get: { (tuner.noiseGate + 75) / 45 },
                                                set: { tuner.noiseGate = (-75 + $0 * 45).rounded() }))
                        .padding(.top, 8)
                    Text("выше — не реагирует на гул").font(Typo.caption).foregroundStyle(Theme.textTertiary).padding(.top, 6)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            Text("Тише порога тюнер молчит. Шумно в комнате — поднимите порог; тихий звукосниматель — опустите.")
                .font(Typo.caption).foregroundStyle(Theme.textTertiary).lineSpacing(12 * 0.4 - 2.5).padding(.horizontal, 4).padding(.vertical, 1.15)   // lh 1.4: half-leading above and below
        }
        .onChange(of: tuner.noiseGate) { UserDefaults.standard.set(tuner.noiseGate, forKey: SettingsHooks.noiseGateKey) }
    }
}

/// «Цель»: the strings of the tuning or the nearest semitone (the tuner's «Авто» / «Хром.»).
struct TargetPage: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let chromatic = app.tuner.choice == .chromatic
        Card {
            CheckRow(title: "Струны строя", subtitle: "тюнер ищет ближайшую струну", selected: !chromatic, minHeight: 61) {
                app.tuner.choice = .auto
            }
            CheckRow(title: "Ближайшая ступень", subtitle: "любая нота, без привязки к строю", selected: chromatic, minHeight: 61,
                     showsDivider: false) {
                app.tuner.choice = .chromatic
            }
        }
    }
}

/// «Обозначение нот»: names (English, solfège, German), accidentals of the current tuning and a preview.
struct NotationPage: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let n = app.settings.notation
        VStack(spacing: 14) {
            VStack(spacing: 0) {
                SectionCaption(text: "Названия")
                Card {
                    CheckRow(title: "C D E F G A B", subtitle: "английское", selected: n == .international, minHeight: 61) { app.settings.notation = .international }
                    CheckRow(title: "До Ре Ми Фа Соль Ля Си", subtitle: "сольфеджио", selected: n == .solfege, minHeight: 61) { app.settings.notation = .solfege }
                    CheckRow(title: "C D E F G A H", subtitle: "немецкое: H вместо B", selected: n == .german, minHeight: 61,
                             showsDivider: false) { app.settings.notation = .german }
                }
            }
            Card {
                CardRow(title: "Знаки", showsDivider: false, minHeight: 57) {
                    Segments(options: [(AccidentalPreference.sharp, "♯"), (.flat, "♭"), (.auto, "Авто")],
                             selection: Binding(get: { app.tuning.accidentalPreference }, set: { setAccidentals($0) }))
                        .frame(width: 150)
                }
            }
            VStack(spacing: 0) {
                SectionCaption(text: "Как будет выглядеть")
                Card {
                    FlowLayout(spacing: 8) {
                        ForEach(Array(Self.preview(app.tuning.accidentalPreference).enumerated()), id: \.offset) { _, name in
                            Typo.notes(app.formatter.string(name), size: 15).foregroundStyle(Theme.textPrimary)
                                .padding(.horizontal, 8)
                                .frame(minWidth: 36, minHeight: 36)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// The accidentals live on the tuning (the tuning editor has the same switch); here — for the current one.
    private func setAccidentals(_ value: AccidentalPreference) {
        guard let id = app.instrument.currentTuningId else { return }
        app.updateInstrument { instrument in
            guard let i = instrument.tunings.firstIndex(where: { $0.id == id }) else { return }
            instrument.tunings[i].accidentalPreference = value
            instrument.tunings[i].isTemplateCopy = false
        }
    }

    /// The 12 notes from E (the guitar's low string): ♯, ♭ or the usual mix (C♯ E♭ F♯ G♯ B♭).
    static func preview(_ preference: AccidentalPreference) -> [NoteName] {
        (0..<12).map { i in
            let pc = (4 + i) % 12
            switch preference {
            case .sharp: return NoteName.simpleSpelling(ofPitchClass: pc, preferFlats: false)
            case .flat: return NoteName.simpleSpelling(ofPitchClass: pc, preferFlats: true)
            case .auto: return NoteName.simpleSpelling(ofPitchClass: pc, preferFlats: pc == 3 || pc == 10)
            }
        }
    }
}

/// «Частота настройки (A4)»: − value +, presets, «Сыграть A4» and which tunings have their own A4.
struct A4Page: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let a4 = app.settings.defaultA4
        VStack(spacing: 14) {
            HStack(spacing: 18) {
                RoundIconButton(icon: .minus, size: 48, iconSize: 20, label: "Меньше") { set(a4 - 1) }
                VStack(spacing: 4) {
                    Text("\(Int(a4))").font(Typo.fixed(56, .extraLight)).foregroundStyle(Theme.textPrimary)
                        .frame(height: 56)
                    Text("Гц · от \(Int(Tuning.a4Range.lowerBound)) до \(Int(Tuning.a4Range.upperBound))").font(Typo.caption).foregroundStyle(Theme.textTertiary)
                }
                RoundIconButton(icon: .plus, size: 48, iconSize: 20, label: "Больше") { set(a4 + 1) }
            }
            .frame(maxWidth: .infinity)
            .padding(19)   // 18 + the 1 pt border outside the content box (CSS)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.cardFill))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.hairline, lineWidth: 1))
            HStack(spacing: 6) {
                ForEach([415, 432, 440, 442, 443], id: \.self) { value in
                    let selected = Int(a4) == value
                    Button { set(Double(value)) } label: {
                        Text("\(value)").font(Typo.inter(14)).foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity).frame(height: 40)
                            .background(Capsule().fill(Color.white.opacity(selected ? 0.1 : 0.05)))
                            .overlay(Capsule().strokeBorder(selected ? Color(hex: 0xf3efe6, opacity: 0.6) : Theme.hairlineStrong, lineWidth: 1))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Card {
                CardRow(title: "Сыграть A4", subtitle: "проверить на слух", showsDivider: false, minHeight: 59) {
                    RoundIconButton(icon: .play, size: 36, iconSize: 16, label: "Сыграть A4") {
                        app.audio.playNote(Pitch(cents: 0), a4: app.settings.defaultA4)
                    }
                }
            }
            VStack(spacing: 0) {
                SectionCaption(text: "Строи · у каких свой A4")
                Card {
                    let tunings = app.instrument.tunings
                    ForEach(Array(tunings.enumerated()), id: \.element.id) { index, tuning in
                        tuningRow(tuning, a4: a4, last: index == tunings.count - 1)
                    }
                }
            }
        }
    }

    @ViewBuilder private func tuningRow(_ tuning: Tuning, a4: Double, last: Bool) -> some View {
        if let own = tuning.a4, own != a4 {
            Button {
                app.showSettings = false
                app.sheet = .tuningEditor(tuning.id)
            } label: {
                CardRow(title: tuning.name, showsDivider: !last, minHeight: 53) {
                    HStack(spacing: 8) {
                        Text("\(SettingsFormat.hz(own)) · свой")
                        Icon(.chevronRight, size: 16, color: Theme.textTertiary)
                    }
                }
            }
            .buttonStyle(.plain)
        } else {
            CardRow(title: tuning.name, showsDivider: !last, minHeight: 53) { Text("\(SettingsFormat.hz(a4)) · как здесь") }
        }
    }

    private func set(_ value: Double) {
        app.settings.defaultA4 = value.clamped(to: Tuning.a4Range)
        app.tuner.tuningChanged()
    }
}

extension SettingsFormat {
    /// «440», «441,5» (decimal comma, no «,0»).
    static func hz(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }
}

// MARK: - Sound

/// «Вход»: built-in microphone, wired headset and USB interface (those not connected are shown dimmed), input number
/// on multi-input interfaces, a big level meter with the good zone, the noise threshold (AU-2, AU-7).
struct InputPage: View {
    @Environment(AppModel.self) private var app
    @AppStorage("tuner.inputChannel") private var channel = 0
    var openNoise: () -> Void = {}

    struct Device: Identifiable {
        var id: String
        var title: String
        var subtitle: String?
        var connected: Bool
        var channels = 1
    }

    /// Connected inputs plus a row for each usual kind that is missing (canvas: «не подключена», «подключите — появится
    /// здесь»).
    private var devices: [Device] {
        #if os(iOS)
        let ports = AVAudioSession.sharedInstance().availableInputs ?? []
        var result: [Device] = []
        if let mic = ports.first(where: { $0.portType == .builtInMic }) {
            result.append(Device(id: mic.uid, title: "Встроенный микрофон", connected: true, channels: mic.channels?.count ?? 1))
        }
        if let headset = ports.first(where: { $0.portType == .headsetMic }) {
            result.append(Device(id: headset.uid, title: headset.portName, connected: true))
        } else {
            result.append(Device(id: "headset", title: "Проводная гарнитура", subtitle: "не подключена", connected: false))
        }
        let usb = ports.filter { [.usbAudio, .lineIn].contains($0.portType) }
        for port in usb {
            let n = port.channels?.count ?? 1
            result.append(Device(id: port.uid, title: port.portName, subtitle: n > 1 ? "\(n) \(n < 5 ? "входа" : "входов")" : nil,
                                 connected: true, channels: n))
        }
        if usb.isEmpty {
            result.append(Device(id: "usb", title: "USB-интерфейс", subtitle: "подключите — появится здесь", connected: false))
        }
        for port in ports where ![.builtInMic, .headsetMic, .usbAudio, .lineIn].contains(port.portType) {
            result.append(Device(id: port.uid, title: port.portName, connected: true, channels: port.channels?.count ?? 1))
        }
        return result
        #else
        return [Device(id: "default", title: "Микрофон", connected: true)]
        #endif
    }

    private var currentUID: String? {
        #if os(iOS)
        // Without an active recording session the route has no input: the built-in microphone is the default.
        return app.audio.session.currentInputUID
            ?? AVAudioSession.sharedInstance().availableInputs?.first(where: { $0.portType == .builtInMic })?.uid
        #else
        return "default"
        #endif
    }

    /// `-inputLevelDemo <bars>`: a fixed level for screenshots, in lit bars of 24 (the board shows 12).
    private var level: Double? {
        if let demo = UserDefaults.standard.string(forKey: "inputLevelDemo"), let bars = Double(demo) { return LevelMeter.levelFor(bars: bars) }
        return app.tuner.isListening ? app.tuner.level : nil
    }

    var body: some View {
        let list = devices
        let current = currentUID
        VStack(spacing: 14) {
            VStack(spacing: 0) {
                SectionCaption(text: "Устройство")
                Card {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, device in
                        CheckRow(title: device.title, subtitle: device.subtitle, selected: device.connected && device.id == current,
                                 dimmed: !device.connected, minHeight: device.subtitle == nil ? 53 : 59,
                                 showsDivider: index < list.count - 1,
                                 action: action(for: device))
                    }
                }
            }
            if let device = list.first(where: { $0.id == current }), device.channels > 1 {
                VStack(spacing: 0) {
                    SectionCaption(text: "Номер входа")
                    Card {
                        ForEach(0..<device.channels, id: \.self) { ch in
                            CheckRow(title: "Вход \(ch + 1)", subtitle: ch == 0 ? "Hi-Z · гитара" : nil, selected: channel == ch,
                                     minHeight: ch == 0 ? 59 : 53, showsDivider: ch < device.channels - 1) {
                                channel = ch
                                app.tuner.handleAudioRestart()
                            }
                        }
                    }
                }
            }
            VStack(spacing: 0) {
                SectionCaption(text: "Уровень сигнала")
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        LevelMeter(level: level)
                        HStack(spacing: 0) {
                            Text("тихо")
                            Spacer(minLength: 0)
                            Text("хорошо").foregroundStyle(Theme.inTune)
                            Spacer(minLength: 0)
                            Text("громко")
                        }
                        .font(Typo.caption).foregroundStyle(Theme.textTertiary)
                        Text(level == nil ? "Уровень виден, пока открыт тюнер." : "Сыграйте открытую струну: полоса должна доходить до зелёной зоны.")
                            .font(Typo.inter(13)).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                }
            }
            Card {
                Button(action: openNoise) {
                    CardRow(title: "Порог шума", subtitle: "выше — не реагирует на гул", showsDivider: false, minHeight: 59) {
                        HStack(spacing: 8) {
                            Text(SettingsFormat.decibels(app.tuner.noiseGate))
                            Icon(.chevronRight, size: 16, color: Theme.textTertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func action(for device: Device) -> (() -> Void)? {
        guard device.connected else { return nil }
        return { select(device) }
    }

    private func select(_ device: Device) {
        #if os(iOS)
        try? app.audio.session.selectInput(uid: device.id)
        app.tuner.handleAudioRestart()
        #endif
    }
}

/// The level of the corrected canvas: 24 bars 8…31 pt, gap 3, radius 2; lit — ivory, green in the good zone (bars
/// 15–20), orange above it; unlit — white 12 %, the good zone green 35 %. −70…0 dBFS.
struct LevelMeter: View {
    let level: Double?
    static let count = 24
    static let zone = 14..<20

    /// The level that lights `bars` bars.
    static func levelFor(bars: Double) -> Double { -70 + (bars + 0.5) / Double(count) * 70 }

    var body: some View {
        let lit = level.map { Int((($0 + 70) / 70).clamped(to: 0...1) * Double(Self.count)) } ?? 0
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<Self.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color(i, lit: i < lit))
                    .frame(maxWidth: .infinity)
                    .frame(height: 8 + CGFloat(i))
            }
        }
        .frame(height: 34, alignment: .bottom)
        .accessibilityElement()
        .accessibilityLabel(level.map { "Уровень входа \(Int($0)) дБ" } ?? "Уровень входа недоступен")
    }

    private func color(_ i: Int, lit: Bool) -> Color {
        let inZone = Self.zone.contains(i)
        if lit { return i >= Self.zone.upperBound ? Theme.sharp : (inZone ? Theme.inTune : Theme.beat) }
        return inZone ? Theme.inTune.opacity(0.35) : Color.white.opacity(0.12)
    }
}

/// «Выход звука»: where the metronome, notes and the reference sound go, Bluetooth delay warning, latency correction.
struct OutputPage: View {
    @Environment(AppModel.self) private var app
    var openCheck: () -> Void = {}

    struct Output: Identifiable {
        var id: String
        var title: String
        var subtitle: String?
        var current = false
        var warning = false
        var speaker = false
    }

    private var outputs: [Output] {
        if UserDefaults.standard.bool(forKey: "audioRoutesDemo") {
            // The board's sample: AirPods and a USB interface connected, the phone speaker in use.
            return [Output(id: "speaker", title: "Динамик телефона", current: true, speaker: true),
                    Output(id: "wired", title: "Проводные наушники", subtitle: "не подключены"),
                    Output(id: "bt", title: "AirPods", subtitle: "задержка ~180 мс — метроном будет опаздывать", warning: true),
                    Output(id: "usb", title: "USB-интерфейс", subtitle: "Focusrite 2i2 · выход 1–2")]
        }
        #if os(iOS)
        let route = AVAudioSession.sharedInstance().currentRoute.outputs
        let latency = Int((AVAudioSession.sharedInstance().outputLatency * 1000).rounded())
        var result = [Output(id: "speaker", title: "Динамик телефона",
                             current: route.contains { $0.portType == .builtInSpeaker || $0.portType == .builtInReceiver }, speaker: true)]
        if let wired = route.first(where: { $0.portType == .headphones }) {
            result.append(Output(id: wired.uid, title: "Проводные наушники", current: true))
        } else {
            result.append(Output(id: "wired", title: "Проводные наушники", subtitle: "не подключены"))
        }
        for port in route where [.bluetoothA2DP, .bluetoothLE, .bluetoothHFP].contains(port.portType) {
            let late = latency > 50
            result.append(Output(id: port.uid, title: port.portName,
                                 subtitle: late ? "задержка ~\(latency) мс — метроном будет опаздывать" : nil, current: true, warning: late))
        }
        if let usb = route.first(where: { [.usbAudio, .lineOut, .HDMI, .airPlay, .carAudio].contains($0.portType) }) {
            let n = usb.channels?.count ?? 2
            let title = usb.portType == .usbAudio ? "USB-интерфейс" : usb.portName
            result.append(Output(id: usb.uid, title: title, subtitle: usb.portType == .usbAudio ? "\(usb.portName) · выход 1–\(n)" : nil, current: true))
        } else {
            result.append(Output(id: "usb", title: "USB-интерфейс", subtitle: "подключите — появится здесь"))
        }
        return result
        #else
        return [Output(id: "default", title: "Выход системы", current: true)]
        #endif
    }

    private var offset: Double { app.settings.latencyOffsets[app.audio.outputName] ?? 0 }

    var body: some View {
        let list = outputs
        VStack(spacing: 14) {
            VStack(spacing: 0) {
                SectionCaption(text: "Куда звучат метроном, ноты и эталон")
                Card {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, output in
                        CheckRow(title: output.title, subtitle: output.subtitle, selected: output.current,
                                 titleColor: output.warning ? Theme.sharp : nil, minHeight: 61,
                                 showsDivider: index < list.count - 1,
                                 action: action(for: output))
                    }
                }
            }
            VStack(spacing: 0) {
                SectionCaption(text: "Задержка")
                Card {
                    CardRow(title: "Поправка задержки", subtitle: "если щелчок отстаёт от вспышки", minHeight: 69) {
                        ValueStepper(value: (offset > 0 ? "+" : "") + "\(Int(offset)) мс", canDecrement: offset > -100, canIncrement: offset < 400,
                                     decrement: { LatencySection.set(app, offset - 5) }, increment: { LatencySection.set(app, offset + 5) })
                    }
                    Button(action: openCheck) {
                        CardRow(title: "Проверить на слух", subtitle: "щелчок и вспышка одновременно?", showsDivider: false, minHeight: 61) {
                            Icon(.chevronRight, size: 16, color: Theme.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func action(for output: Output) -> (() -> Void)? {
        if output.speaker { return { route(toSpeaker: true) } }
        return output.current ? { route(toSpeaker: false) } : nil
    }

    /// iOS picks the route itself; the app can only force the speaker or give the route back (AirPlay / Bluetooth are
    /// chosen in Control Center).
    private func route(toSpeaker: Bool) {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().overrideOutputAudioPort(toSpeaker ? .speaker : .none)
        app.audio.applyLatency()
        #endif
    }
}

/// «Громкость и задержка» (SND-7, ME-9): click, notes and chords, reference and drone; output latency.
struct VolumePage: View {
    @Environment(AppModel.self) private var app
    @AppStorage("vol.click") private var click = 0.8
    @AppStorage("vol.notes") private var notes = 0.6
    @AppStorage("vol.reference") private var reference = 0.5

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 0) {
                SectionCaption(text: "Громкость")
                Card {
                    slider("Щелчок метронома", icon: .metronome, value: $click, caption: "сильная доля громче")
                    slider("Ноты и аккорды", icon: .music, value: $notes, caption: "гитарный тембр")
                    slider("Эталон и бурдон", icon: .waveform, value: $reference, caption: "тюнер", last: true)
                }
            }
            Text("Беззвучный режим iPhone не глушит Truver. Пока телефон звучит, тюнер не слушает.")
                .font(Typo.caption).foregroundStyle(Theme.textTertiary).lineSpacing(12 * 0.4 - 2.5).padding(.horizontal, 4).padding(.vertical, 1.15)   // lh 1.4: half-leading above and below
                .fixedSize(horizontal: false, vertical: true)
            LatencySection()
        }
        .onChange(of: click) { apply() }
        .onChange(of: notes) { apply() }
        .onChange(of: reference) { apply() }
    }

    private func apply() {
        app.audio.host.setVolumes(click: Float(click), notes: Float(notes), reference: Float(reference))
    }

    private func slider(_ title: String, icon: AppIcon, value: Binding<Double>, caption: String, last: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(title).font(Typo.row).foregroundStyle(Theme.textBody)
                Spacer()
                Text("\(Int((value.wrappedValue * 100).rounded())) %").font(Typo.inter(14)).foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 10) {
                Icon(icon, size: 16, color: Theme.textTertiary)
                VolumeSlider(value: value)
            }
            .padding(.top, 8)
            Text(caption).font(Typo.caption).foregroundStyle(Theme.textTertiary).padding(.top, 6)
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 14)   // measured on the board: 97 pt a row
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) } }
    }
}

/// Slider of the corrected canvas: 24 pt tall, 4 pt track (white 12 %), ivory fill, white 24 pt knob.
struct VolumeSlider: View {
    @Binding var value: Double

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let v = value.clamped(to: 0...1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12)).frame(height: 4)
                Capsule().fill(Theme.accent).frame(width: w * v, height: 4)
                Circle().fill(Color.white).frame(width: 24, height: 24)
                    .offset(x: w * v - 12)
            }
            .frame(height: 24)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in value = (g.location.x / w).clamped(to: 0...1) })
        }
        .frame(height: 24)
        .accessibilityElement()
        .accessibilityValue("\(Int(value * 100)) процентов")
        .accessibilityAdjustableAction { d in value = (value + (d == .increment ? 0.05 : -0.05)).clamped(to: 0...1) }
    }
}

/// ME-9: output latency = what the system reports + a manual correction for this output. The check plays the
/// metronome; the play button flashes on the beat as the timeline sees it — move the correction until the flash and
/// the click land together.
struct LatencySection: View {
    @Environment(AppModel.self) private var app
    @State private var pulse = false
    @State private var showsHelp = false

    private var name: String { app.audio.outputName }
    private var offset: Double { app.settings.latencyOffsets[name] ?? 0 }

    /// «Задержка · динамик»: the speaker in lower case, device names as they are.
    private var caption: String { name == "Динамик" ? "динамик" : name }

    var body: some View {
        let system = Int((app.audio.systemOutputLatency * 1000).rounded())
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 0) {
                SectionCaption(text: "Задержка · \(caption)")
                Card {
                    CardRow(title: "Из системы", minHeight: 51) {
                        Text("\(system) мс")
                    }
                    CardRow(title: "Поправка", subtitle: "итого \(max(0, system + Int(offset))) мс", minHeight: 59) {
                        ValueStepper(value: (offset > 0 ? "+" : "") + "\(Int(offset))", canDecrement: offset > -100, canIncrement: offset < 400,
                                     decrement: { Self.set(app, offset - 5) }, increment: { Self.set(app, offset + 5) })
                    }
                    CardRow(title: "Проверить на слух", subtitle: "щелчок и вспышка совпадают?", showsDivider: offset != 0, minHeight: 59) {
                        RoundIconButton(icon: app.metronome.isPlaying ? .stop : .play, size: 36, iconSize: 16,
                                        label: app.metronome.isPlaying ? "Стоп" : "Проверить") { app.metronome.toggle() }
                            .overlay(Circle().fill(Theme.beat).opacity(pulse ? 0.9 : 0).allowsHitTesting(false))
                    }
                    if offset != 0 {
                        Button { Self.set(app, 0) } label: {
                            CardRow(title: "Сбросить поправку", showsDivider: false, minHeight: 51) { EmptyView() }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Button { withAnimation(Motion.out(Motion.Duration.quick)) { showsHelp.toggle() } } label: {
                    Text("Bluetooth-наушники опаздывают · как настроить ›").font(Typo.inter(13)).foregroundStyle(Theme.textSecondary)
                        // CSS: a 13 pt span in a 16 pt line box sits ~3 pt lower.
                        .padding(.top, 3)
                }
                .buttonStyle(.plain)
                if showsHelp {
                    Text("Наушники Bluetooth часто звучат позже, чем говорит система. Включите проверку и меняйте поправку, пока вспышка не совпадёт со щелчком. Поправка хранится для каждого выхода и влияет на полосу долей, вспышку и подсветку нот.")
                        .font(Typo.caption).foregroundStyle(Theme.textTertiary).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 4)
        }
        .onChange(of: app.metronome.currentBeat) {
            guard app.metronome.isPlaying else { return }
            pulse = true
            withAnimation(.easeOut(duration: 0.18)) { pulse = false }
        }
    }

    static func set(_ app: AppModel, _ value: Double) {
        let name = app.audio.outputName
        var offsets = app.settings.latencyOffsets
        offsets[name] = value == 0 ? nil : value.clamped(to: -100...400)
        app.settings.latencyOffsets = offsets
    }
}
