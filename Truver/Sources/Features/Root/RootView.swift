import SwiftUI

/// App shell (canvas): the current tab's screen, the tuning pill above a custom tab bar, toasts on top.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.isPhoneLandscape) private var landscape
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        @Bindable var app = app
        ZStack {
            ScreenBackground()
            screen
                .transition(.opacity)
                .id(app.settings.lastTab)
                // VoiceOver stays inside an open sheet (it reached the screen under it — UX check). XCUITest still
                // lists these elements; VoiceOver itself is to be checked by hand on the phone.
                .accessibilityHidden(app.sheet != nil)
        }
        .animation(Motion.out(Motion.Duration.quick), value: app.settings.lastTab)
        .background { KeyCommands() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Landscape boards have no tab bar: the tuner keeps the tuning chip, the other tabs rotate back.
            // The corrected canvas shows the tuning pill on the tuner only (the fretboard names the tuning under its
            // title; metronome and practice boards have none). The pill sits 8 pt above the tab bar (`bottom: 92`).
            // The fretboard's «Таб» is a full screen without the tab bar (canvas S6Tab).
            if !landscape && !(app.settings.lastTab == .fretboard && app.fretboard.hidesTabBar) {
                VStack(spacing: 8) {
                    if TuningPill.isShown(on: app.settings.lastTab) && !TuningPill.largeText(typeSize) { TuningPill().coachAnchor(CoachCatalog.Anchor.tuningPill) }
                    AppTabBar(selection: $app.settings.lastTab)
                }
                .accessibilityHidden(app.sheet != nil)
            }
        }
        // Canvas «Прервано звонком»: the banner at y 698 lies over the tab bar.
        .overlay(alignment: .top) {
            if app.settings.lastTab == .metronome && app.metronome.interrupted && !landscape && app.sheet == nil {
                MetronomeInterruptionBanner().padding(.horizontal, 20).padding(.top, 698).ignoresSafeArea()
            }
        }
        .overlay { SheetHost() }
        .overlay(alignment: .top) {
            if let notice = app.notice {
                Group {
                    if let icon = app.noticeIcon {
                        DesignToast(icon: icon, iconColor: app.noticeIconColor, text: notice).padding(.top, 62)
                    } else {
                        ToastView(text: notice).padding(.top, 54)
                    }
                }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Motion.out(Motion.Duration.base), value: app.notice)
        #if os(iOS)
        .fullScreenCover(isPresented: $app.showSettings) { SettingsView() }
        #else
        .sheet(isPresented: $app.showSettings) { SettingsView().frame(minWidth: 420, minHeight: 640) }
        #endif
        #if os(iOS)
        .fullScreenCover(isPresented: $app.showSession) { PracticeSessionView().environment(app) }
        #else
        .sheet(isPresented: $app.showSession) { PracticeSessionView().environment(app).frame(minWidth: 420, minHeight: 760) }
        #endif
        #if os(iOS)
        .fullScreenCover(isPresented: $app.showTrainer, onDismiss: { app.trainer.close() }) {
            FretTrainerView().environment(app).onAppear { app.trainer.open() }
        }
        #else
        .sheet(isPresented: $app.showTrainer, onDismiss: { app.trainer.close() }) {
            FretTrainerView().environment(app).frame(minWidth: 420, minHeight: 760).onAppear { app.trainer.open() }
        }
        #endif
        #if os(iOS)
        .fullScreenCover(isPresented: $app.showOnboarding) { OnboardingView() }
        #else
        .sheet(isPresented: $app.showOnboarding) { OnboardingView().frame(minWidth: 420, minHeight: 760) }
        #endif
        .onAppear { app.updateListening() }
        .onChange(of: app.settings.lastTab) { app.updateListening() }
        .onChange(of: app.showOnboarding) { app.updateListening() }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var screen: some View {
        switch app.settings.lastTab {
        case .tuner: TunerScreen()
        case .fretboard: FretboardScreen()
        case .metronome: MetronomeScreen()
        case .practice: PracticeScreen()
        }
    }
}

/// «8-струнная · Drop E ▾» above the tab bar: the tuning switcher (6, 6.1 п. 2). Canvas: a 40 pt button, padding 18,
/// radius 20, border white 8 %, card fill, 14 medium, chevron 14, gap 8, shadow `0 8px 20px` black 50 %.
struct TuningPill: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Tabs whose boards show the pill (the tuner only since the corrected canvas).
    static func isShown(on tab: AppTab) -> Bool { tab == .tuner }

    /// Large-text boards (FixTunerLarge, MetroLargeText) have no pill; `-tunerLarge` forces the tuner's large layout.
    static func largeText(_ size: DynamicTypeSize) -> Bool {
        size.isAccessibilitySize || ProcessInfo.processInfo.arguments.contains("-tunerLarge")
    }

    var body: some View {
        Button {
            if app.isSmartModeRunning {
                app.show("Остановите упражнение, чтобы сменить строй", icon: .lock)
            } else { app.sheet = .tunings }
        } label: {
            HStack(spacing: 8) {
                // Large text (canvas): only the tuning name, 18 pt, a 270 × 48 button.
                Text(typeSize.isAccessibilitySize ? app.tuning.name : app.title)
                    .font(typeSize.isAccessibilitySize ? Typo.fixed(18) : Typo.inter(14, .medium)).lineLimit(1)
                // Canvas «переключатель заблокирован»: a lock instead of the chevron while an exercise runs.
                Icon(app.isSmartModeRunning ? .lock : .chevronDown, size: 14, color: Theme.textTertiary)
            }
            .foregroundStyle(Theme.textBody)
            .padding(.horizontal, 18)
            .frame(minWidth: typeSize.isAccessibilitySize ? 270 : nil)
            .frame(height: typeSize.isAccessibilitySize ? 48 : 40)
            .background(Capsule(style: .circular).fill(Theme.cardFill))
            .overlay(Capsule(style: .circular).strokeBorder(Theme.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 10, y: 8)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Строй: \(app.title)")
    }
}

/// Custom tab bar of the canvas: 84 pt with the home-indicator area (50 above it), background #0a0b0d at 96 %, top
/// hairline white 6 %, padding 8; items: icon 24 at 13 pt from the top (border 1 + padding 8 + 4), label 11 four
/// points below — ivory semibold when selected, tertiary regular otherwise. A playing metronome shows a dot on its
/// icon breathing with the strong beats (motion spec, «Навигация»).
struct AppTabBar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var selection: AppTab

    private let items: [(AppTab, AppIcon, String)] = [
        (.tuner, .tuner, "Тюнер"), (.fretboard, .fretboard, "Гриф"), (.metronome, .metronome, "Метроном"), (.practice, .practice, "Занятия"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.0) { tab, icon, title in
                let selected = selection == tab
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        Icon(icon, size: 24, lineWidth: 1.5, color: selected ? Theme.textPrimary : Theme.textTertiary)
                            .overlay(alignment: .topTrailing) {
                                if tab == .metronome && app.metronome.isPlaying {
                                    Circle().fill(Theme.textPrimary)
                                        .frame(width: 6, height: 6)
                                        .opacity(app.metronome.currentBeat == 0 ? 1 : 0.45)
                                        .animation(Motion.out(Motion.Duration.tick), value: app.metronome.currentBeat)
                                        .offset(x: 3, y: -1)
                                }
                            }
                        // Large text (corrected canvas «Тюнер / Метроном — крупный шрифт»): the labels stay, at 11 pt.
                        Text(title).font(typeSize.isAccessibilitySize ? Typo.fixed(11, selected ? .semibold : .regular)
                                                                      : (selected ? Typo.tabSelected : Typo.tab))
                            .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
                    }
                    .padding(.top, 13)
                    .frame(maxWidth: .infinity, maxHeight: 50, alignment: .top)
                    .frame(height: 50, alignment: .top)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .background(Theme.background.opacity(0.96).ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
    }
}

/// Presents `app.sheet`: dim fades in (280 ms), the panel rises 60 pt with fade (340 ms, «out»).
struct SheetHost: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack(alignment: .bottom) {
            if app.sheet != nil {
                Theme.sheetDim.ignoresSafeArea()
                    .onTapGesture { app.sheet = nil }
                    .accessibilityElement()
                    .accessibilityLabel("Закрыть лист")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { app.sheet = nil }
                    .transition(.opacity.animation(.easeOut(duration: 0.28)))
            }
            if let sheet = app.sheet {
                content(sheet)
                    // The panel reaches the bottom edge of the screen (canvas: top … bottom 0); the footer keeps
                    // 34 pt for the home indicator itself.
                    .ignoresSafeArea(.container, edges: .bottom)
                    .transition(.asymmetric(insertion: .offset(y: 60).combined(with: .opacity), removal: .move(edge: .bottom)))
                    .id(sheet)
                    .accessibilityAddTraits(.isModal)
                    .accessibilityAction(.escape) { app.sheet = nil }     // two-finger scrub closes it
            }
        }
        .animation(Motion.out(0.34), value: app.sheet)
    }

    @ViewBuilder private func content(_ sheet: AppSheet) -> some View {
        switch sheet {
        case .metroMeter: MeterSheet()
        case .metroRhythm: RhythmSheet()
        case .metroRhythmBeat(let beat): RhythmSheet(beat: beat)
        case .metroModes: ModesSheet()
        case .metroModeParams(let kind): ModeParamsSheet(kind: kind)
        case .metroPresets: PresetsSheet()
        case .metroSounds: SoundsSheet()
        case .metroTimer: TimerSheet()
        case .fretScale: FretScaleSheet()
        case .fretView: FretViewSheet()
        case .fretPlay: FretPlaySheet()
        case .tunings: TuningsSheet()
        case .tuningsAdd: TuningsAddSheet()
        case .tuningEditor(let id): TuningEditorSheet(tuningId: id)
        case .library: LibrarySheet()
        case .templateCard(let id): TemplateCardSheet(templateId: id)
        case .generator: GeneratorSheet()
        case .instrument: InstrumentSheet()
        case .instrumentRebuild(let count): InstrumentRebuildSheet(newCount: count)
        case .instrumentStrings: InstrumentStringsSheet()
        case .chordsFromNote(let c, let f): ChordsFromNoteSheet(spot: NeckSpot(course: c, fret: f))
        case .scaleFromNote(let c, let f): ScaleFromNoteSheet(spot: NeckSpot(course: c, fret: f))
        case .searchResults: SearchResultsSheet()
        case .fretPath: FretPathSheet()
        case .fretProgression: FretProgressionSheet()
        case .fretProgressions: FretProgressionsSheet()
        case .progressionFromNote(let c, let f): ProgressionFromNoteSheet(spot: NeckSpot(course: c, fret: f))
        case .progressionChord(let index): ProgressionChordSheet(index: index)
        case .progressionInsert(let at): ProgressionChordSheet(index: nil, insertAt: at)
        case .scaleBuilder(let id): ScaleBuilderSheet(editingId: id)
        case .chordBuilder(let id): ChordBuilderSheet(editingId: id)
        case .intonation: IntonationSheet()
        case .tunerPro: TunerProSheet()
        case .playCheck: PlayCheckSheet()
        case .playCheckSummary: PlayCheckSummarySheet()
        }
    }
}

/// Hardware keys and Bluetooth page-turner pedals (they send arrows or Page Up / Down): Space — metronome
/// start/stop, ← → — tempo ∓1 (⇧ — ∓10), ↑ ↓ / Page Up / Page Down — previous / next preset (keeps playing),
/// T — tap tempo, ⌘1…⌘4 — tabs. Hidden zero-size buttons: shortcuts work without focus.
struct KeyCommands: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            key(.space) { app.metronome.toggle() }
            key(.leftArrow) { app.metronome.step(-1) }
            key(.rightArrow) { app.metronome.step(1) }
            key(.leftArrow, .shift) { app.metronome.step(-10) }
            key(.rightArrow, .shift) { app.metronome.step(10) }
            key(.upArrow) { stepPreset(-1) }
            key(.downArrow) { stepPreset(1) }
            key(.pageUp) { stepPreset(-1) }
            key(.pageDown) { stepPreset(1) }
            key("t") { app.metronome.tapTempo() }
            key("1", .command) { app.settings.lastTab = .tuner }
            key("2", .command) { app.settings.lastTab = .fretboard }
            key("3", .command) { app.settings.lastTab = .metronome }
            key("4", .command) { app.settings.lastTab = .practice }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func key(_ k: KeyEquivalent, _ modifiers: EventModifiers = [], action: @escaping () -> Void) -> some View {
        Button("", action: action).keyboardShortcut(k, modifiers: modifiers)
    }

    /// Next / previous preset — a pedal walks a set list; the metronome keeps playing from the next bar.
    private func stepPreset(_ delta: Int) {
        let m = app.metronome
        let presets = m.state.presets
        guard !presets.isEmpty else { return }
        let current = presets.firstIndex { $0.id == m.state.currentPresetId } ?? (delta > 0 ? -1 : presets.count)
        let next = min(presets.count - 1, max(0, current + delta))
        guard next != current else { return }
        m.load(presets[next])
        app.show("\(presets[next].name) · \(Int(presets[next].settings.bpm))", icon: .list)
    }
}
