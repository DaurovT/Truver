import SwiftUI
import TruverTheory

// «Инструмент и строи» by the canvas (6.2.3, corrected boards of 25.11.2026): the instrument and its tunings, adding
// (library by kind, step-by-step generator, by hand), the editor, the instrument and its strings. Heights are
// 844 − the panel's top on the canvas. «Добавить строй», the library and the generator lie over the tunings sheet
// (a second dim, as on the canvas).

// MARK: Debug launch arguments (canvas boards)

/// `-tuningsDemo` (five tunings of the boards), `-sheet tuningsLastOne | tuningsDelete | tuningUnsaved | libraryDrop |
/// generatorDropC` — the same names on Android (lib/features/instrument/instrument_feature.dart).
enum TuningsDebug {
    nonisolated(unsafe) static var lastOneToast = false
    nonisolated(unsafe) static var deleteLast = false
    nonisolated(unsafe) static var unsaved = false
    nonisolated(unsafe) static var libraryCategory: TuningCategory?
    nonisolated(unsafe) static var generator: TuningRecipe?

    @MainActor static func apply(_ arguments: [String], app: AppModel) {
        if arguments.contains("-tuningsDemo") {
            app.updateInstrument { inst in
                let t = { (id: String) in TuningTemplates.template(id: id)!.makeTuning() }
                let standard = inst.currentTuning ?? t("g6-standard-e")
                var half = standard.shifted(bySemitones: -1)
                half.id = UUID(); half.name = "Полтона ниже"; half.accidentalPreference = .sharp; half.templateId = nil
                inst.tunings = [standard, t("g6-drop-d"), half, t("g6-dadgad"), t("g6-open-g")]
                inst.currentTuningId = standard.id
            }
        }
        guard let i = arguments.firstIndex(of: "-sheet"), i + 1 < arguments.count else { return }
        switch arguments[i + 1] {
        case "tuningsLastOne": lastOneToast = true; app.sheet = .tunings
        case "tuningsDelete": deleteLast = true; app.sheet = .tunings
        case "tuningUnsaved": unsaved = true; app.sheet = .tuningEditor(app.tuning.id)
        case "libraryDrop": libraryCategory = .drop; app.sheet = .library
        case "generatorDropC": generator = .drop(lowest: 4, rest: 2); app.sheet = .generator
        default: break
        }
    }
}

// MARK: Shared pieces

/// «≡» of the canvas: three lines and a ring on the top one, filled with the background (16 pt in rows, 22 in cards).
struct EditGlyph: View {
    var size: CGFloat = 16
    var color: Color = Theme.textTertiary

    var body: some View {
        let s = size / 24
        ZStack(alignment: .topLeading) {
            Icon(.list, size: size, color: color)
            Circle().fill(Theme.background)
                .overlay(Circle().stroke(color, lineWidth: 1.6 * s))
                .frame(width: 4 * s, height: 4 * s)
                .offset(x: 7 * s, y: 5 * s)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A row of the tunings list and the library (60 pt): check column 20, name 15, notes 12 with 0.06 em tracking.
struct TuningListRow<Trailing: View>: View {
    let name: String
    let notes: String
    var checked = false
    var showsDivider = true
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            ZStack { if checked { Icon(.check, size: 18, lineWidth: 2, color: Theme.textPrimary) } }.frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Typo.notes(name, size: 15).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Typo.notes(notes, size: 12).tracking(0.72).foregroundStyle(Theme.textTertiary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
        .ruled(showsDivider)
        .contentShape(Rectangle())
    }
}

extension View {
    /// The canvas row's `border-bottom: 1px` below its height (content-box: a 52 pt row takes 53).
    func ruled(_ on: Bool = true) -> some View {
        VStack(spacing: 0) {
            self
            if on { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
        }
    }
}

/// `HStack(spacing: 8) { Text(value); chevron }` — the trailing of a row that opens something.
private func valueChevron(_ value: String, notes: Bool = false) -> some View {
    HStack(spacing: 8) {
        if notes { Typo.notes(value, size: 14) } else { Text(value) }
        Icon(.chevronRight, size: 16, color: Theme.textTertiary)
    }
}

/// A sheet lying over «Инструмент и строи»: the tunings sheet stays below under a second dim (canvas boards
/// «Добавить строй», «Библиотека строев», «Генератор строя»).
struct OverTunings<Sheet: View>: View {
    @Environment(AppModel.self) private var app
    @ViewBuilder var sheet: () -> Sheet

    var body: some View {
        ZStack(alignment: .bottom) {
            TuningsSheet().allowsHitTesting(false).accessibilityHidden(true)
            Theme.sheetDim.ignoresSafeArea()
                .onTapGesture { app.sheet = .tunings }
            sheet()
        }
    }
}

/// Stepper whose value is 48 wide and wraps («2 / тона» on the canvas): − 36, value, + 36, gap 4.
private struct NarrowStepper: View {
    let value: String
    var canDecrement = true
    var canIncrement = true
    let decrement: () -> Void
    let increment: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            RoundIconButton(icon: .minus, size: 36, iconSize: 16, label: "Меньше", action: decrement)
                .disabled(!canDecrement).opacity(canDecrement ? 1 : 0.4)
            Text(value).font(Typo.inter(16)).foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center).frame(width: 48)   // canvas: min-width 44, laid out 48 («2 тона» wraps)
            RoundIconButton(icon: .plus, size: 36, iconSize: 16, label: "Больше", action: increment)
                .disabled(!canIncrement).opacity(canIncrement ? 1 : 0.4)
        }
        .accessibilityElement(children: .contain)
    }
}

/// A row whose title wraps next to a stepper, 10 pt apart (canvas flex `space-between`, gap 10; `CardRow` keeps
/// 28 pt there and wraps the title earlier).
private struct StepperRow<S: View>: View {
    let title: String
    @ViewBuilder var stepper: () -> S

    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(Typo.row).foregroundStyle(Theme.textBody).frame(maxWidth: .infinity, alignment: .leading)
            stepper()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 60)
    }
}

// MARK: «Инструмент и строи»

/// «Инструмент и строи» (top 150): the instrument (→ «Инструмент»), tunings (tap — switch, ≡ — edit, swipe —
/// delete), «Добавить строй». The last tuning can't be deleted — a toast says so.
struct TuningsSheet: View {
    @Environment(AppModel.self) private var app
    @State private var openRow: UUID?
    @State private var deleting: Tuning?
    @State private var lastOneToast = false

    var body: some View {
        let tunings = app.instrument.tunings
        let single = tunings.count == 1
        DesignSheet(title: "Инструмент и строи", height: 694, close: { app.sheet = nil }) {
            VStack(spacing: 14) {
                VStack(spacing: 0) {
                    SectionCaption(text: "Инструмент")
                    Card {
                        Button { app.sheet = .instrument } label: {
                            CardRow(title: app.instrument.name, showsDivider: false, minHeight: 52) {
                                valueChevron("\(app.instrument.fretCount) \(ModeParamsSheet.plural(app.instrument.fretCount, "лад", "лада", "ладов"))")
                            }.ruled()
                        }
                        .buttonStyle(.plain)
                    }
                }
                VStack(spacing: 0) {
                    SectionCaption(text: single ? "Строи" : "Строи · касание — переключить, ≡ — править")
                    Card {
                        ForEach(tunings) { tuning in
                            SwipeRow(id: tuning.id, open: $openRow, showsDivider: false, rename: nil,
                                     delete: { if single { showLastOne() } else { deleting = tuning } }) { row(tuning) }
                        }
                        addRow
                    }
                }
                if lastOneToast {
                    DesignToast(icon: .lock, iconColor: Theme.textSecondary, text: "Последний строй удалить нельзя — сначала добавьте другой")
                        .padding(.horizontal, -20)
                        .padding(.top, 5)
                        .transition(.opacity.combined(with: .offset(y: -14)))
                }
            }
        }
        // Alerts cover the whole screen and sit at its middle (canvas `top: 50%`), not the sheet's.
        .frame(maxHeight: .infinity, alignment: .bottom)
        .overlay {
            Group {
                if let tuning = deleting {
                    DesignAlert(title: "Удалить «\(tuning.name)»?", message: "Строй пропадёт из списка. Пресеты и занятия не затронет.",
                                actions: [.init(title: "Отмена") { deleting = nil },
                                          .init(title: "Удалить", role: .destructive) {
                                              app.deleteTuning(tuning.id)
                                              deleting = nil
                                              openRow = nil
                                          }],
                                dismiss: { deleting = nil })
                }
            }
            .ignoresSafeArea()
        }
        .onAppear {
            if TuningsDebug.deleteLast { TuningsDebug.deleteLast = false; deleting = tunings.last }
            if TuningsDebug.lastOneToast { TuningsDebug.lastOneToast = false; lastOneToast = true }
        }
    }

    private func showLastOne() {
        withAnimation(Motion.out(Motion.Duration.base)) { lastOneToast = true }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(Motion.out(Motion.Duration.base)) { lastOneToast = false }
        }
    }

    private func row(_ tuning: Tuning) -> some View {
        let current = tuning.id == app.tuning.id
        return TuningListRow(name: tuning.name, notes: tuning.spelledNotes.map { app.noteName($0) }.joined(separator: " "), checked: current) {
            Button { app.sheet = .tuningEditor(tuning.id) } label: {
                EditGlyph().frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(-14)
            .accessibilityLabel("Изменить строй \(tuning.name)")
        }
        .onTapGesture {
            app.selectTuning(tuning.id)
            app.sheet = nil
        }
        .accessibilityAddTraits(current ? [.isSelected, .isButton] : .isButton)
    }

    /// «+ Добавить строй» (52 pt) at the end of the list.
    private var addRow: some View {
        Button { app.sheet = .tuningsAdd } label: {
            HStack(spacing: 10) {
                Icon(.plus, size: 18, color: Theme.textPrimary)
                Text("Добавить строй").font(Typo.inter(15)).foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: «Добавить строй»

/// «Добавить строй» (top 420, over the tunings): from the library, generated, by hand.
struct TuningsAddSheet: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let count = TuningTemplates.library(for: app.instrument, category: nil).count
        OverTunings {
            DesignSheet(title: "Добавить строй", height: 424, close: { app.sheet = .tunings }) {
                VStack(spacing: 10) {
                    option(title: "Из библиотеки", subtitle: "\(count) \(ModeParamsSheet.plural(count, "готовый строй", "готовых строя", "готовых строев")): Drop, Open, полтона ниже и др.") {
                        Icon(.search, size: 22, color: Theme.textBody)
                    } action: { app.sheet = .library }
                    option(title: "Сгенерировать", subtitle: "Опустить строй, сделать Drop или Open — по шагам") {
                        EditGlyph(size: 22, color: Theme.textBody)
                    } action: { app.sheet = .generator }
                    option(title: "Вручную", subtitle: "Ноту каждой струны выбираете сами") {
                        Icon(.plus, size: 22, color: Theme.textBody)
                    } action: { addManual() }
                }
            }
        }
    }

    /// Card 16 pt padding: icon tile 44 (radius 12), title 16 semibold, subtitle 12 (line height 1.35), chevron.
    private func option<I: View>(title: String, subtitle: String, @ViewBuilder icon: () -> I, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                icon()
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Typo.inter(16, .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(subtitle).font(Typo.inter(12)).foregroundStyle(Theme.textSecondary).lineSpacing(1.7)
                        .padding(.vertical, 0.85)   // CSS line-height 1.35: half-leading above and below too
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Icon(.chevronRight, size: 16, color: Theme.textTertiary)
            }
            .padding(17)   // padding 16 + the 1 pt border outside it (CSS content-box)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.cardFill))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    /// «Вручную»: a copy of the current tuning, not saved until «Сохранить».
    private func addManual() {
        var copy = app.tuning
        copy.id = UUID()
        copy.name = TuningEditorSheet.uniqueName("Свой строй", in: app.instrument)
        copy.isTemplateCopy = false
        copy.templateId = nil
        app.unsavedTuning = copy
        app.sheet = .tuningEditor(copy.id)
    }
}

// MARK: «Редактор строя»

/// «<строй> · редактор» (top 54): strings from the lowest (cents offset, ± semitone), A4 and accidentals, frets and
/// capo of the instrument; the list scrolls in a 560 pt window with a fade. Leaving with changes asks «Сохранить
/// изменения?» — «Сохранить как «Drop D»» when the edit makes another library tuning. The title renames.
struct TuningEditorSheet: View {
    @Environment(AppModel.self) private var app
    let tuningId: UUID
    @State private var draft: Tuning?
    @State private var askSave = false
    @State private var naming = false
    @State private var name = ""

    /// The tuning as stored, or the unsaved copy being created.
    private var original: Tuning? {
        app.instrument.tunings.first { $0.id == tuningId } ?? app.unsavedTuning.flatMap { $0.id == tuningId ? $0 : nil }
    }
    private var isNew: Bool { !app.instrument.tunings.contains { $0.id == tuningId } }

    var body: some View {
        let original = self.original
        let tuning = draft ?? original
        DesignSheet(title: "\(tuning?.name ?? "Строй") · редактор", height: 790, close: close) {
            VStack(spacing: 0) {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.horizontal, -20)
                ZStack(alignment: .bottom) {
                    ScrollView {
                        if let tuning { fields(tuning).padding(.bottom, 40) }
                    }
                    .scrollIndicators(.hidden)
                    LinearGradient(colors: [Theme.panel.opacity(0), Theme.panel], startPoint: .top, endPoint: .bottom)
                        .frame(height: 40).allowsHitTesting(false)
                }
                .frame(height: 560)
                .padding(.top, 12)
            }
        } footer: {
            SheetButton(title: "Сохранить") { save(); exit() }
        }
        .overlay(alignment: .topLeading) {
            // The title renames the tuning (the canvas has no «Название» row any more).
            Color.clear.frame(width: 280, height: 40).contentShape(Rectangle())
                .onTapGesture { name = tuning?.name ?? ""; naming = true }
                .padding(.top, 28).padding(.leading, 20)
                .accessibilityElement().accessibilityLabel("Переименовать строй").accessibilityAddTraits(.isButton)
        }
        // Alerts cover the whole screen and sit at its middle (canvas `top: 50%`), not the sheet's.
        .frame(maxHeight: .infinity, alignment: .bottom)
        .overlay {
            Group {
                if askSave, let original, let tuning { saveAlert(original: original, draft: tuning) }
                if naming {
                    TextFieldAlert(title: "Название строя", text: $name, cancel: { naming = false }, save: {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty { edit { $0.name = trimmed } }
                        naming = false
                    })
                }
            }
            .ignoresSafeArea()
        }
        .onAppear {
            // Canvas «Сохранить изменения?»: the 6th string E2 → D2.
            if TuningsDebug.unsaved, let original {
                TuningsDebug.unsaved = false
                var t = original
                t.openCents[0] = t.openCents[0].map { $0 - 200 }
                t.isTemplateCopy = false
                draft = t
                askSave = true
            }
        }
    }

    @ViewBuilder private func fields(_ tuning: Tuning) -> some View {
        VStack(spacing: 14) {
            VStack(spacing: 0) {
                SectionCaption(text: "Струны · от низкой · шаг — полутон")
                Card {
                    ForEach(tuning.openCents.indices, id: \.self) { course in stringRow(tuning, course: course) }
                }
            }
            VStack(spacing: 0) {
                SectionCaption(text: "Строй")
                Card {
                    // A4 of this tuning right here (it opened the Settings root and lost the editor — UX check).
                    Menu {
                        Button("Как в настройках · \(Int(app.settings.defaultA4)) Гц") { edit { $0.a4 = nil } }
                        ForEach([415, 430, 432, 435, 438, 440, 441, 442, 443, 444, 446], id: \.self) { hz in
                            Button("\(hz) Гц") { edit { $0.a4 = Double(hz) } }
                        }
                    } label: {
                        CardRow(title: "A4", showsDivider: false) {
                            valueChevron(tuning.a4.map { "\(Int($0)) Гц" } ?? "Как в настройках · \(Int(app.settings.defaultA4)) Гц")
                        }.ruled()
                    }
                    .buttonStyle(.plain)
                    CardRow(title: "Знаки", showsDivider: false) {
                        Segments(options: [(AccidentalPreference.sharp, "♯"), (.flat, "♭"), (.auto, "Авто")],
                                 selection: Binding(get: { tuning.accidentalPreference }, set: { v in edit { $0.accidentalPreference = v } }),
                                 size: .compact)
                            .frame(width: 150)
                    }.ruled()
                }
            }
            // Frets and capo belong to the instrument, but they are looked for here (user: «почему в редакторе
            // строя нету?») — they apply at once to every tuning of this instrument.
            VStack(spacing: 0) {
                SectionCaption(text: "Гриф · для всего инструмента")
                Card {
                    Menu {
                        ForEach(Array(Set([20, 21, 22, 24, 27, app.instrument.fretCount])).sorted(), id: \.self) { n in
                            Button("\(n) \(ModeParamsSheet.plural(n, "лад", "лада", "ладов"))") { app.updateInstrument { $0.fretCount = n } }
                        }
                    } label: {
                        CardRow(title: "Ладов", showsDivider: false) { valueChevron("\(app.instrument.fretCount)") }.ruled()
                    }
                    .buttonStyle(.plain)
                    Menu {
                        Button("Нет") { app.updateInstrument { $0.capo = 0 } }
                        ForEach(1...12, id: \.self) { fret in Button("\(fret)-й лад") { app.updateInstrument { $0.capo = fret } } }
                    } label: {
                        CardRow(title: "Капо", showsDivider: false) { valueChevron(app.instrument.capo == 0 ? "Нет" : "\(app.instrument.capo)-й лад") }.ruled()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// 60 pt: number 13 (14 wide), note 18, offset «0 ц» 12, − 40 · note 16 medium (46) · + 40.
    private func stringRow(_ tuning: Tuning, course: Int) -> some View {
        let offset = tuning.offsetsCents[safe: course]?.first ?? 0
        // The tuning's own spelling (E♭ standard after lowering, not D♯), not the chromatic default.
        let spelled = tuning.spelledNotes[safe: course].map { app.noteName($0) } ?? app.chromaticName(tuning.openPitch(course: course))
        return HStack(spacing: 12) {
            Text("\(tuning.openCents.count - course)").font(Typo.inter(13)).foregroundStyle(Theme.textTertiary).frame(width: 14, alignment: .leading)
            Typo.notes(spelled, size: 18).foregroundStyle(Theme.textPrimary).frame(maxWidth: .infinity, alignment: .leading)
            // PR-3 «нота или центы»: the cents are their own control (± stays a semitone).
            Menu {
                ForEach([-50, -30, -20, -10, -5, 0, 5, 10, 20, 30, 50], id: \.self) { c in
                    Button(c == 0 ? "0 ц" : "\(c > 0 ? "+" : "−")\(abs(c)) ц") { setCents(course, Double(c)) }
                }
            } label: {
                Text(offset == 0 ? "0 ц" : "\(offset > 0 ? "+" : "−")\(Int(abs(offset))) ц")
                    .font(Typo.inter(12)).foregroundStyle(offset == 0 ? Theme.textTertiary : Theme.sharp)
            }
            .accessibilityLabel("Отстройка в центах: \(Int(offset))")
            HStack(spacing: 2) {
                RoundIconButton(icon: .minus, size: 40, iconSize: 16, label: "Ниже на полутон") { shift(course, -1) }
                Typo.notes(spelled, size: 16, weight: .medium).foregroundStyle(Theme.textPrimary).frame(width: 46)
                RoundIconButton(icon: .plus, size: 40, iconSize: 16, label: "Выше на полутон") { shift(course, 1) }
            }
        }
        .padding(.leading, 16).padding(.trailing, 12)
        .frame(height: 60)
        .ruled()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Струна \(tuning.openCents.count - course), \(spelled)")
    }

    /// «Сохранить изменения?»: another library tuning → «Сохранить как «Drop D»» / «Заменить «Стандарт E»»;
    /// otherwise «Сохранить» / «Сохранить как новый»; «Не сохранять» last.
    private func saveAlert(original: Tuning, draft: Tuning) -> some View {
        let change = TuningChange(original: original, draft: draft, instrument: app.instrument, formatter: app.formatter)
        var actions: [DesignAlert.Action]
        if isNew {
            actions = [.init(title: "Сохранить", role: .preferred) { askSave = false; save(); exit() }]
        } else if let match = change.match {
            actions = [.init(title: "Сохранить как «\(match)»", role: .preferred) { askSave = false; saveAsNew(draft, name: match) },
                       .init(title: "Заменить «\(original.name)»") { askSave = false; save(); exit() }]
        } else {
            actions = [.init(title: "Сохранить", role: .preferred) { askSave = false; save(); exit() },
                       .init(title: "Сохранить как новый") { askSave = false; saveAsNew(draft, name: draft.name) }]
        }
        actions.append(.init(title: "Не сохранять", role: .destructive) { askSave = false; leave() })
        return DesignAlert(title: "Сохранить изменения?", message: isNew ? "Строй «\(draft.name)» ещё не сохранён." : change.message,
                           actions: actions, dismiss: { askSave = false })
    }

    private func edit(_ change: (inout Tuning) -> Void) {
        guard var t = draft ?? original else { return }
        change(&t)
        t.isTemplateCopy = false
        draft = t
    }

    private func setCents(_ course: Int, _ cents: Double) {
        edit { t in
            if t.offsetsCents.count != t.openCents.count {
                t.offsetsCents = t.openCents.map { $0.map { _ in 0 } }
            }
            t.offsetsCents[course] = t.offsetsCents[course].map { _ in cents }
        }
    }

    private func shift(_ course: Int, _ semitones: Int) {
        edit { $0.openCents[course] = $0.openCents[course].map { $0 + Double(semitones) * 100 } }
    }

    private func save() {
        if isNew {
            guard let tuning = draft ?? original else { return }
            app.updateInstrument { try? $0.addTuning(tuning) }
            app.unsavedTuning = nil
            return
        }
        guard let draft else { return }
        app.updateInstrument { instrument in
            if let i = instrument.tunings.firstIndex(where: { $0.id == draft.id }) { instrument.tunings[i] = draft }
        }
    }

    /// The edit as another tuning; the original stays as it was.
    private func saveAsNew(_ draft: Tuning, name: String) {
        var copy = draft
        copy.id = UUID()
        copy.name = Self.uniqueName(name, in: app.instrument)
        copy.templateId = TuningTemplates.matching(copy.coursePitches, instrument: app.instrument)?.id
        app.updateInstrument { try? $0.addTuning(copy) }
        exit()
    }

    private func close() {
        if let draft, draft != original { askSave = true } else { leave() }
    }

    /// Leaving without saving drops an unsaved copy.
    private func leave() {
        if isNew { app.unsavedTuning = nil }
        exit()
    }

    private func exit() {
        app.sheet = app.tuningEditorFromTuner ? nil : .tunings
        app.tuningEditorFromTuner = false
    }

    /// «Drop D», «Drop D (2)»…
    static func uniqueName(_ base: String, in instrument: Instrument) -> String {
        let names = Set(instrument.tunings.map(\.name))
        guard names.contains(base) else { return base }
        var n = 2
        while names.contains("\(base) (\(n))") { n += 1 }
        return "\(base) (\(n))"
    }
}

// MARK: «Библиотека строев»

/// «Библиотека строев» (top 60, over the tunings): search, kinds «Все / Drop / Open / Ниже / Альтернативные», templates
/// for this instrument with «+» or «добавлен»; a row opens the template card. Nothing found → generator or by hand.
struct LibrarySheet: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""
    @State private var category: TuningCategory?

    var body: some View {
        let base = TuningTemplates.library(for: app.instrument, category: category)
        let list = query.isEmpty ? base : base.filter { matches($0) }
        let n = app.instrument.courses.count
        OverTunings {
            DesignSheet(title: "Библиотека строев", height: 784, close: { app.sheet = .tunings }) {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Icon(.search, size: 16, color: Theme.textTertiary)
                        TextField("", text: $query, prompt: Text("Поиск: Drop, Open, ноты…").foregroundColor(Theme.textTertiary))
                            .font(Typo.inter(15)).foregroundStyle(Theme.textPrimary)
                    }
                    .padding(.horizontal, 14).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            chip("Все", nil)
                            ForEach([TuningCategory.drop, .open, .lower, .alternative], id: \.self) { chip($0.title, $0) }
                        }
                        .padding(.horizontal, 20)
                    }
                    .scrollIndicators(.hidden)
                    .padding(.horizontal, -20)
                    if list.isEmpty {
                        empty
                    } else {
                        ForEach(groups(list), id: \.0) { kind, templates in
                            VStack(spacing: 0) {
                                SectionCaption(text: "\(kind.title) · \(n) \(ModeParamsSheet.plural(n, "струна", "струны", "струн"))")
                                Card {
                                    ForEach(templates) { templateRow($0) }
                                }
                            }
                        }
                        Text("Показаны строи для \(n) \(n % 10 == 1 && n % 100 != 11 ? "струны" : "струн"). Другие инструменты — сменить вверху списка строёв.")
                            .font(Typo.inter(12)).foregroundStyle(Theme.textTertiary).lineSpacing(2.3)
                            .padding(.vertical, 1.15)   // CSS line-height 1.4: half-leading above and below too
                            .padding(.horizontal, 4).padding(.top, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .onAppear {
            if let c = TuningsDebug.libraryCategory { TuningsDebug.libraryCategory = nil; category = c }
        }
    }

    private func chip(_ title: String, _ value: TuningCategory?) -> some View {
        Button { withAnimation(Motion.out(Motion.Duration.quick)) { category = value } } label: {
            Chip(text: title, style: category == value ? .emphasized : .plain)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(category == value ? .isSelected : [])
    }

    private func matches(_ t: TuningTemplate) -> Bool {
        let q = query.lowercased().replacingOccurrences(of: "#", with: "♯")
        return t.names.ru.lowercased().contains(q) || t.names.en.lowercased().contains(q)
            || t.notes.map { app.noteName($0) }.joined(separator: " ").lowercased().contains(q)
    }

    private func groups(_ list: [TuningTemplate]) -> [(TuningCategory, [TuningTemplate])] {
        TuningCategory.allCases.compactMap { kind in
            let items = list.filter { $0.category == kind }
            return items.isEmpty ? nil : (kind, items)
        }
    }

    static func typeName(_ type: InstrumentType) -> String {
        switch type {
        case .guitar, .guitarExtendedHigh: return "гитара"
        case .bass: return "бас"
        case .ukulele: return "укулеле"
        case .mandolin: return "мандолина"
        case .dutar: return "дутар"
        case .tanbur: return "танбур"
        case .rubob: return "рубоб"
        }
    }

    private func templateRow(_ template: TuningTemplate) -> some View {
        let exists = app.instrument.tunings.contains { $0.templateId == template.id || $0.hasSamePitches(template.notes.map(\.pitch)) }
        return TuningListRow(name: template.names.ru, notes: template.notes.map { app.noteName($0) }.joined(separator: " ")) {
            if exists {
                Text("добавлен").font(Typo.inter(11)).foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            } else {
                Button { app.addTemplate(template) } label: {
                    Icon(.plus, size: 18, color: Theme.textPrimary).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(-13)
                .accessibilityLabel("Добавить \(template.names.ru)")
            }
        }
        .onTapGesture { app.sheet = .templateCard(template.id) }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            VStack(spacing: 0) {
                Icon(.search, size: 22, color: Theme.textTertiary)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Theme.fill))
                    .overlay(Circle().strokeBorder(Theme.hairlineStrong, lineWidth: 1))
                Text("Ничего не найдено").font(Typo.inter(17, .medium)).foregroundStyle(Theme.textBody).padding(.top, 12)
                Text("Строя «\(query)» нет. Соберите его сами").font(Typo.caption).foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center).frame(maxWidth: 200).padding(.top, 6)
            }
            .frame(maxWidth: .infinity).padding(18)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.cardFill))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
            HStack(spacing: 10) {
                outline("Сгенерировать") { app.sheet = .generator }
                outline("Вручную") {
                    var copy = app.tuning
                    copy.id = UUID(); copy.name = query.isEmpty ? "Свой строй" : query; copy.isTemplateCopy = false; copy.templateId = nil
                    app.unsavedTuning = copy
                    app.sheet = .tuningEditor(copy.id)
                }
            }
        }
    }

    private func outline(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Typo.inter(15, .medium)).foregroundStyle(Theme.textBody)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Capsule().fill(Theme.cardFill))
                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }
}

/// Template card (top 150): read-only; strings with Hz, intervals, where it is used, A4; «Добавить в мои строи».
struct TemplateCardSheet: View {
    @Environment(AppModel.self) private var app
    let templateId: String

    var body: some View {
        let template = TuningTemplates.template(id: templateId)
        DesignSheet(title: template?.names.ru ?? "Шаблон", height: 694, close: { app.sheet = .library }) {
            if let template {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Chip(text: "Шаблон", icon: .lock, style: .muted)
                        Chip(text: "\(template.courseCount) \(ModeParamsSheet.plural(template.courseCount, "струна", "струны", "струн")) · \(LibrarySheet.typeName(template.type))")
                    }
                    Text("Струны · от низкой · Гц").font(Typo.caption).foregroundStyle(Theme.textTertiary)
                    HStack(spacing: 4) {
                        ForEach(Array(template.notes.enumerated()), id: \.offset) { index, note in
                            VStack(spacing: 4) {
                                Text("\(template.courseCount - index)").font(Typo.inter(11)).foregroundStyle(Theme.textTertiary)
                                Typo.notes(app.noteName(note), size: 14, weight: .semibold).foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1).minimumScaleFactor(0.6)
                                    .frame(maxWidth: .infinity, minHeight: 40)
                                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.cardFill))
                                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                                Text(Self.hz(note, a4: app.settings.defaultA4)).font(Typo.inter(10)).foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                    Card {
                        CardRow(title: "Интервалы") { Typo.notes(intervals(template), size: 14).multilineTextAlignment(.trailing) }
                        CardRow(title: "Где встречается") { Text(usage(template)).multilineTextAlignment(.trailing) }
                        CardRow(title: "A4", showsDivider: false) { Text("\(Int(app.settings.defaultA4)) Гц") }
                    }
                    Text("Шаблон не редактируется. После добавления — обычный строй, его можно менять")
                        .font(Typo.caption).foregroundStyle(Theme.textTertiary)
                }
            }
        } footer: {
            SheetButton(title: "Добавить в мои строи", icon: .plus) {
                if let template { app.addTemplate(template) }
                app.sheet = .tunings
            }
        }
    }

    static func hz(_ note: SpelledNote, a4: Double) -> String {
        let f = 440 * pow(2, Double(note.midi - 69) / 12) * a4 / 440
        return f < 100 ? String(format: "%.1f", f) : String(Int(f.rounded()))
    }

    /// «кварты, B3 — терция».
    private func intervals(_ template: TuningTemplate) -> String {
        let steps = zip(template.notes.dropFirst(), template.notes).map { $0.midi - $1.midi }
        let names = [3: "м. терция", 4: "терция", 5: "кварта", 7: "квинта", 2: "секунда", 12: "октава"]
        let common = Dictionary(grouping: steps, by: { $0 }).max { $0.value.count < $1.value.count }?.key ?? 5
        var parts = [common == 5 ? "кварты" : (names[common].map { $0 + "ы" } ?? "\(common) полутонов")]
        for (i, s) in steps.enumerated() where s != common {
            parts.append("\(app.noteName(template.notes[i + 1])) — \(names[s] ?? "\(s) полутонов")")
        }
        return parts.joined(separator: ", ")
    }

    private func usage(_ template: TuningTemplate) -> String {
        let n = template.courseCount
        let type = LibrarySheet.typeName(template.type)
        if template.id.contains("standard") { return "стандарт для \(n)-струнной \(type == "гитара" ? "гитары" : type)" }
        if template.id.contains("drop") { return "дроп-строй: нижняя струна на тон ниже" }
        return "\(n) \(ModeParamsSheet.plural(n, "струна", "струны", "струн")) · \(type)"
    }
}

// MARK: «Генератор строя»

/// «Генератор строя» (top 150, over the tunings): from the current tuning — Drop (the lowest string down by N, the
/// others by M), everything lower, Open (a major chord); «Получится» with a slack warning; «Добавить «Drop C»» or,
/// when such a tuning is already saved, «Переключиться на …».
struct GeneratorSheet: View {
    @Environment(AppModel.self) private var app
    @State private var mode = Mode.drop
    @State private var dropLowest = 2
    @State private var dropRest = 0
    @State private var lower = 1
    @State private var openRoot = 7

    enum Mode: Hashable { case drop, lower, open }

    private var recipe: TuningRecipe {
        switch mode {
        case .drop: return .drop(lowest: dropLowest, rest: dropRest)
        case .lower: return .lower(semitones: lower)
        case .open: return .open(root: openRoot)
        }
    }

    var body: some View {
        let result = recipe.apply(to: app.tuning, instrument: app.instrument, formatter: app.formatter)
        let same = app.instrument.tunings.first { $0.hasSamePitches(result.pitches) }
        let n = app.instrument.courses.count
        OverTunings {
            DesignSheet(title: "Генератор строя", height: 694, close: { app.sheet = .tunings }) {
                VStack(spacing: 14) {
                    VStack(spacing: 0) {
                        SectionCaption(text: "Что сделать")
                        Card {
                            Segments(options: [(Mode.drop, "Drop"), (.lower, "Ниже всё"), (.open, "Open")], selection: $mode)
                                .padding(6)
                        }
                    }
                    VStack(spacing: 0) {
                        SectionCaption(text: "Параметры")
                        Card { parameters(strings: n) }
                    }
                    VStack(spacing: 0) {
                        SectionCaption(text: "Получится")
                        Card {
                            VStack(alignment: .leading, spacing: 8) {
                                Typo.notes(result.name, size: 20, weight: .semibold).foregroundStyle(Theme.textPrimary)
                                Typo.notes(result.notes.map { app.noteName($0) }.joined(separator: " "), size: 15)
                                    .tracking(1.2).foregroundStyle(Theme.textBody)
                                if let warning = result.warning {
                                    Text(warning).font(Typo.inter(12)).foregroundStyle(Theme.sharp)
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            } footer: {
                if let same {
                    SheetButton(title: "Переключиться на «\(same.name)»") {
                        app.selectTuning(same.id)
                        app.sheet = .tunings
                    }
                } else {
                    SheetButton(title: "Добавить «\(result.name)»") { add(result) }
                }
            }
        }
        .onAppear {
            if case let .drop(lowest, rest)? = TuningsDebug.generator {
                TuningsDebug.generator = nil
                mode = .drop; dropLowest = lowest; dropRest = rest
            }
        }
    }

    @ViewBuilder private func parameters(strings n: Int) -> some View {
        switch mode {
        case .drop:
            // «на» alone on the second line as on the canvas (iOS Text would otherwise pull «струну» down with it).
            StepperRow(title: "Опустить \(n)-ю струну\nна") {
                NarrowStepper(value: TuningRecipe.tones(dropLowest), canDecrement: dropLowest > dropRest + 1, canIncrement: dropLowest < 12,
                              decrement: { dropLowest -= 1 }, increment: { dropLowest += 1 })
            }.ruled()
            Menu {
                ForEach(0...5, id: \.self) { s in
                    Button(Self.restText(s)) { dropRest = s; dropLowest = max(dropLowest, s + 1) }
                }
            } label: {
                CardRow(title: "Остальные струны", showsDivider: false, minHeight: 52) { valueChevron(Self.restText(dropRest)) }.ruled()
            }
            .buttonStyle(.plain)
        case .lower:
            StepperRow(title: "Опустить все струны на") {
                NarrowStepper(value: TuningRecipe.tones(lower), canDecrement: lower > 1, canIncrement: lower < 12,
                              decrement: { lower -= 1 }, increment: { lower += 1 })
            }.ruled()
        case .open:
            Menu {
                ForEach([7, 2, 4, 9, 0, 5, 11], id: \.self) { pc in
                    Button(noteName(pc)) { openRoot = pc }
                }
            } label: {
                CardRow(title: "Аккорд", showsDivider: false, minHeight: 52) { valueChevron(noteName(openRoot), notes: true) }.ruled()
            }
            .buttonStyle(.plain)
        }
    }

    /// «без изменений», «на полтона ниже», «на 1 тон ниже»…
    static func restText(_ semitones: Int) -> String {
        semitones == 0 ? "без изменений" : "на \(semitones == 1 ? "полтона" : TuningRecipe.tones(semitones)) ниже"
    }

    private func noteName(_ pc: Int) -> String {
        app.formatter.string(NoteName.simpleSpelling(ofPitchClass: pc, preferFlats: false)) + " мажор"
    }

    private func add(_ result: TuningRecipe.Result) {
        let flats = result.notes.contains { $0.name.accidental < 0 }
        let tuning = Tuning(name: TuningEditorSheet.uniqueName(result.name, in: app.instrument),
                            openCents: zip(result.pitches, app.instrument.courses).map { pitch, course in
                                course.pairing == .octave ? [pitch.cents, pitch.cents + 1200]
                                    : Array(repeating: pitch.cents, count: course.strings.count)
                            },
                            accidentalPreference: flats ? .flat : (result.notes.contains { $0.name.accidental > 0 } ? .sharp : .auto),
                            templateId: result.templateId)
        app.updateInstrument { try? $0.addTuning(tuning) }
        app.sheet = .tunings
    }
}

/// «Инструмент» (top 150): name, type, strings (with rebuild), paired courses, frets, capo; strings and scale.
struct InstrumentSheet: View {
    @Environment(AppModel.self) private var app
    @State private var naming = false
    @State private var name = ""

    var body: some View {
        let i = app.instrument
        DesignSheet(title: "Инструмент", height: 694, close: { app.sheet = .tunings }) {
            VStack(spacing: 14) {
                Card {
                    Button { name = i.name; naming = true } label: {
                        CardRow(title: "Название", showsDivider: false, minHeight: 52) { Text(i.name) }.ruled()
                    }
                    .buttonStyle(.plain)
                    CardRow(title: "Тип", showsDivider: false, minHeight: 52) { valueChevron(LibrarySheet.typeName(i.type).capitalizedFirst) }.ruled()
                    CardRow(title: "Число струн", subtitle: "строи пересоберутся", showsDivider: false, minHeight: 62) {
                        ValueStepper(value: "\(i.courses.count)", canDecrement: i.courses.count > 1, canIncrement: i.courses.count < 12,
                                     decrement: { app.sheet = .instrumentRebuild(i.courses.count - 1) },
                                     increment: { app.sheet = .instrumentRebuild(i.courses.count + 1) })
                    }.ruled()
                    CardRow(title: "Сдвоенные курсы", showsDivider: false, minHeight: 52) {
                        ToggleSwitch(isOn: Binding(get: { i.courses.contains { $0.pairing != .single } },
                                                   set: { on in
                                                       app.updateInstrument { inst in
                                                           for c in inst.courses.indices {
                                                               inst = InstrumentEditing.changingPairing(of: inst, course: c, to: on ? .unison : .single).0
                                                           }
                                                       }
                                                   }), label: "Сдвоенные курсы")
                    }.ruled()
                    CardRow(title: "Число ладов", subtitle: "обычно 21–27", showsDivider: false, minHeight: 62) {
                        ValueStepper(value: "\(i.fretCount)", canDecrement: i.fretCount > 12, canIncrement: i.fretCount < 30,
                                     decrement: { app.updateInstrument { $0.fretCount -= 1 } }, increment: { app.updateInstrument { $0.fretCount += 1 } })
                    }.ruled()
                    Menu {
                        Button("Нет") { app.updateInstrument { $0.capo = 0 } }
                        ForEach(1...12, id: \.self) { fret in Button("\(fret)-й лад") { app.updateInstrument { $0.capo = fret } } }
                    } label: {
                        CardRow(title: "Капо", showsDivider: false, minHeight: 52) { valueChevron(i.capo == 0 ? "Нет" : "\(i.capo)-й лад") }.ruled()
                    }
                    .buttonStyle(.plain)
                }
                VStack(spacing: 0) {
                    SectionCaption(text: "Струны")
                    Card {
                        Button { app.sheet = .instrumentStrings } label: {
                            CardRow(title: "Калибры и мензура", showsDivider: false, minHeight: 52) { valueChevron(scaleText) }.ruled()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } footer: {
            SheetButton(title: "Готово") { app.sheet = .tunings }
        }
        // Alerts cover the whole screen and sit at its middle (canvas `top: 50%`), not the sheet's.
        .frame(maxHeight: .infinity, alignment: .bottom)
        .overlay {
            Group {
                if naming {
                    TextFieldAlert(title: "Название инструмента", text: $name, cancel: { naming = false }, save: {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty { app.updateInstrument { $0.name = trimmed } }
                        naming = false
                    })
                }
            }
            .ignoresSafeArea()
        }
    }

    private var scaleText: String {
        if let m = app.instrument.multiscale {
            return "\(Int(m.bassScaleLength.rounded()))–\(Int(m.trebleScaleLength.rounded())) мм"
        }
        let lengths = app.instrument.courses.compactMap { $0.strings.first?.scaleLength }
        return lengths.first.map { "\(Int($0)) мм" } ?? "\(Self.defaultScale(app.instrument)) мм"
    }

    static func defaultScale(_ i: Instrument) -> Int {
        switch i.type {
        case .bass: return 864
        case .ukulele: return 330
        case .mandolin: return 350
        default: return i.courses.count >= 8 ? 686 : (i.courses.count == 7 ? 648 : 648)
        }
    }
}

/// «9 струн вместо 8» (top 230): side, affected tunings with the added note, low-range warning.
struct InstrumentRebuildSheet: View {
    @Environment(AppModel.self) private var app
    let newCount: Int
    @State private var side = InstrumentEditing.Side.low

    var body: some View {
        let old = app.instrument.courses.count
        let preview = InstrumentEditing.changingStringCount(of: app.instrument, to: newCount, side: side).0
        DesignSheet(title: "\(newCount) \(ModeParamsSheet.plural(newCount, "струна", "струны", "струн")) вместо \(old)", height: 614,
                    close: { app.sheet = .instrument }) {
            VStack(alignment: .leading, spacing: 14) {
                Text(newCount > old ? "Строи пересоберутся: в каждом появится новая струна на кварту от крайней."
                                    : "Строи пересоберутся: крайняя струна уйдёт из каждого строя.")
                    .font(Typo.inter(14)).foregroundStyle(Theme.textSecondary)
                VStack(alignment: .leading, spacing: 8) {
                    Text("С какой стороны").font(Typo.caption).foregroundStyle(Theme.textTertiary)
                    Segments(options: [(InstrumentEditing.Side.low, "Снизу"), (.high, "Сверху")], selection: $side)
                }
                VStack(spacing: 0) {
                    SectionCaption(text: "Затронутые строи")
                    Card {
                        ForEach(Array(preview.tunings.enumerated()), id: \.element.id) { index, tuning in
                            CardRow(title: tuning.name, showsDivider: index < preview.tunings.count - 1) {
                                Typo.notes(change(tuning, old: old), size: 14)
                            }
                        }
                    }
                }
                if let low = lowestBelowRange(preview) {
                    HStack(spacing: 8) {
                        Icon(.warning, size: 14, color: Theme.sharp)
                        Typo.notes(low, size: 13).foregroundStyle(Theme.sharp)
                    }
                }
            }
        } footer: {
            Button { app.sheet = .instrument } label: {
                Text("Отмена").font(Typo.button).foregroundStyle(Theme.textBody)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(Capsule().fill(Theme.cardFill))
                    .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
            SheetButton(title: "Пересобрать") {
                app.updateInstrument { $0 = InstrumentEditing.changingStringCount(of: $0, to: newCount, side: side).0 }
                app.sheet = .instrument
            }
        }
    }

    private func change(_ tuning: Tuning, old: Int) -> String {
        guard newCount > old else { return "− струна" }
        let index = side == .low ? 0 : tuning.openCents.count - 1
        guard let cents = tuning.openCents[safe: index]?.first else { return "" }
        return "+ " + app.chromaticName(Pitch(cents: cents))
    }

    /// «B0 ≈ 31 Гц — нижняя граница тюнера».
    private func lowestBelowRange(_ instrument: Instrument) -> String? {
        let lowest = instrument.tunings.flatMap { $0.openCents.compactMap(\.first) }.min()
        guard let lowest else { return nil }
        let pitch = Pitch(cents: lowest)
        let f = pitch.frequency(a4: app.settings.defaultA4)
        guard f < 33 else { return nil }
        return "\(app.chromaticName(pitch)) ≈ \(Int(f.rounded())) Гц — нижняя граница тюнера"
    }
}

/// «Струны» (top 60): scale length (one for all, fan frets — v1.x), string set, gauges per string.
struct InstrumentStringsSheet: View {
    @Environment(AppModel.self) private var app
    @State private var editing: Int?
    @State private var editingScale = false
    @State private var editingFan: FanField?
    @State private var text = ""

    enum FanField { case bass, treble }

    var body: some View {
        let i = app.instrument
        DesignSheet(title: "Струны", height: 784, close: { app.sheet = .instrument }) {
            VStack(spacing: 14) {
                Card {
                    CardRow(title: "Веерные лады", subtitle: i.multiscale == nil ? "одна мензура на все струны" : "своя мензура у каждой струны") {
                        ToggleSwitch(isOn: Binding(get: { i.multiscale != nil }, set: { setFanned($0) }), label: "Веерные лады")
                    }
                    if let m = i.multiscale {
                        Button { text = "\(Int(m.bassScaleLength.rounded()))"; editingFan = .bass } label: {
                            CardRow(title: "Басовая струна", subtitle: inches(m.bassScaleLength)) {
                                HStack(spacing: 8) { Text("\(Int(m.bassScaleLength.rounded())) мм"); Icon(.chevronRight, size: 16, color: Theme.textTertiary) }
                            }
                        }
                        .buttonStyle(.plain)
                        Button { text = "\(Int(m.trebleScaleLength.rounded()))"; editingFan = .treble } label: {
                            CardRow(title: "Высокая струна", subtitle: inches(m.trebleScaleLength)) {
                                HStack(spacing: 8) { Text("\(Int(m.trebleScaleLength.rounded())) мм"); Icon(.chevronRight, size: 16, color: Theme.textTertiary) }
                            }
                        }
                        .buttonStyle(.plain)
                        Menu {
                            ForEach(0...14, id: \.self) { fret in
                                Button(fret == 0 ? "Порожек" : "\(fret)-й лад") { updateFan { $0.neutralFret = fret } }
                            }
                        } label: {
                            CardRow(title: "Нейтральный лад", subtitle: "лад под прямым углом к струнам") {
                                HStack(spacing: 8) { Text(m.neutralFret == 0 ? "Порожек" : "\(m.neutralFret)-й"); Icon(.chevronRight, size: 16, color: Theme.textTertiary) }
                            }
                        }
                        .buttonStyle(.plain)
                        Menu {
                            ForEach(Self.fanPresets(for: i), id: \.0) { name, preset in
                                Button(name) { applyFan(preset) }
                            }
                        } label: {
                            CardRow(title: "Типовой веер") {
                                HStack(spacing: 8) { Text(fanPresetName ?? "Свой"); Icon(.chevronRight, size: 16, color: Theme.textTertiary) }
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button { text = "\(scale)"; editingScale = true } label: {
                            CardRow(title: "Мензура", subtitle: "одна на все струны") {
                                HStack(spacing: 8) { Text("\(scale) мм"); Icon(.chevronRight, size: 16, color: Theme.textTertiary) }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    CardRow(title: "Комплект", subtitle: "подставит калибры", showsDivider: false) {
                        Menu {
                            ForEach(Self.sets(for: i), id: \.0) { name, gauges in
                                Button(name) { apply(gauges) }
                            }
                        } label: {
                            HStack(spacing: 8) { Text(currentSet ?? "Свой"); Icon(.chevronRight, size: 16, color: Theme.textTertiary) }
                        }
                    }
                }
                VStack(spacing: 0) {
                    SectionCaption(text: "Калибр струн")
                    Card {
                        ForEach(Array(i.courses.indices.enumerated()), id: \.element) { row, course in
                            stringRow(course, last: row == i.courses.count - 1)
                        }
                    }
                }
            }
        } footer: {
            SheetButton(title: "Готово") { app.sheet = .instrument }
        }
        // Alerts cover the whole screen and sit at its middle (canvas `top: 50%`), not the sheet's.
        .frame(maxHeight: .infinity, alignment: .bottom)
        .overlay {
            Group {
                if let field = editingFan {
                    TextFieldAlert(title: field == .bass ? "Мензура басовой струны, мм" : "Мензура высокой струны, мм", text: $text, cancel: { editingFan = nil }, save: {
                        if let value = Double(text.trimmingCharacters(in: .whitespaces)), (300...1000).contains(value) {
                            updateFan { m in if field == .bass { m.bassScaleLength = value } else { m.trebleScaleLength = value } }
                        }
                        editingFan = nil
                    })
                }
                if editingScale {
                    TextFieldAlert(title: "Мензура, мм", text: $text, cancel: { editingScale = false }, save: {
                        if let value = Int(text.trimmingCharacters(in: .whitespaces)), (300...1000).contains(value) { setScale(value) }
                        editingScale = false
                    })
                }
                if let course = editing {
                    TextFieldAlert(title: "Калибр, дюймы", text: $text, cancel: { editing = nil }, save: {
                        let value = Double(text.replacingOccurrences(of: ",", with: "."))
                        app.updateInstrument { inst in
                            for s in inst.courses[course].strings.indices { inst.courses[course].strings[s].gauge = value }
                        }
                        editing = nil
                    })
                }
            }
            .ignoresSafeArea()
        }
    }

    private var scale: Int {
        Int(app.instrument.courses.first?.strings.first?.scaleLength ?? Double(InstrumentSheet.defaultScale(app.instrument)))
    }

    private func inches(_ mm: Double) -> String {
        String(format: "%.2f″", mm / 25.4).replacingOccurrences(of: ".00″", with: "″").replacingOccurrences(of: "0″", with: "″")
    }

    /// PR-7: on — a typical fan for this instrument; off — one scale (the treble one, as on most single-scale twins).
    private func setFanned(_ on: Bool) {
        if on {
            applyFan(Self.fanPresets(for: app.instrument).first!.1)
        } else {
            let treble = app.instrument.multiscale.map { Int($0.trebleScaleLength.rounded()) } ?? scale
            app.updateInstrument { $0.multiscale = nil }
            setScale(treble)
        }
    }

    private func applyFan(_ m: Multiscale) {
        app.updateInstrument { inst in
            inst.multiscale = m
            Self.syncStrings(&inst)
        }
    }

    private func updateFan(_ change: (inout Multiscale) -> Void) {
        guard var m = app.instrument.multiscale else { return }
        change(&m)
        applyFan(m)
    }

    /// Each string keeps its own scale length too (tension calculator WS-1).
    static func syncStrings(_ inst: inout Instrument) {
        guard let m = inst.multiscale else { return }
        let n = inst.courses.count
        for c in inst.courses.indices {
            for s in inst.courses[c].strings.indices { inst.courses[c].strings[s].scaleLength = m.scaleLength(course: c, courses: n).rounded() }
        }
    }

    private var fanPresetName: String? {
        guard let m = app.instrument.multiscale else { return nil }
        return Self.fanPresets(for: app.instrument).first { $0.1 == m }?.0
    }

    /// Fans of common extended-range guitars and basses (inches, neutral fret).
    static func fanPresets(for i: Instrument) -> [(String, Multiscale)] {
        let list: [(Double, Double, Int)]
        if i.type == .bass {
            list = [(35, 34, 7), (37, 34, 8), (35.5, 33.5, 7)]
        } else {
            switch i.courses.count {
            case ...6: list = [(25.5, 25, 7), (26.5, 25.5, 7), (25.5, 24.75, 7)]
            case 7: list = [(26.5, 25.5, 7), (27, 25.5, 8), (26.25, 25.5, 7)]
            case 8: list = [(27, 25.5, 7), (28, 25.5, 9), (27.2, 25.5, 8)]
            default: list = [(28, 25.5, 8), (28.6, 25.5, 9), (30, 26.5, 9)]
            }
        }
        return list.map { b, t, n in
            let name = "\(Self.inchText(b))–\(Self.inchText(t)) · \(n)-й"
            return (name, Multiscale.inches(b, t, neutralFret: n))
        }
    }

    static func inchText(_ v: Double) -> String {
        v == v.rounded() ? "\(Int(v))″" : String(format: "%g″", v)
    }

    private func setScale(_ value: Int) {
        app.updateInstrument { inst in
            for c in inst.courses.indices { for s in inst.courses[c].strings.indices { inst.courses[c].strings[s].scaleLength = Double(value) } }
        }
    }

    /// 44 pt rows: number, note, gauge field «.074», «оплётка / гладкая», scale.
    private func stringRow(_ course: Int, last: Bool) -> some View {
        let gauge = app.instrument.courses[course].strings.first?.gauge
        let pitch = app.tuning.openCents[safe: course]?.first.map { Pitch(cents: $0) }
        return HStack(spacing: 10) {
            Text("\(app.instrument.courses.count - course)").font(Typo.caption).foregroundStyle(Theme.textTertiary).frame(width: 16, alignment: .leading)
            Typo.notes(pitch.map { app.chromaticName($0) } ?? "", size: 15).foregroundStyle(Theme.textPrimary).frame(width: 36, alignment: .leading)
            Button {
                text = gauge.map { String(format: "%.3f", $0) } ?? ""
                editing = course
            } label: {
                Text(gauge.map { String(format: ".%03d", Int(($0 * 1000).rounded())) } ?? "—")
                    .font(Typo.inter(14)).foregroundStyle(Theme.textPrimary)
                    .frame(width: 70, height: 32, alignment: .leading).padding(.leading, 10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
            Text(gauge.map { $0 >= 0.02 ? "оплётка" : "гладкая" } ?? "калибр не задан").font(Typo.caption).foregroundStyle(Theme.textTertiary)
            Spacer()
            Text("\(app.instrument.multiscale.map { Int($0.scaleLength(course: course, courses: app.instrument.courses.count).rounded()) } ?? scale)")
                .font(Typo.inter(13)).foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 16).frame(minHeight: 44)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) } }
    }

    private var currentSet: String? {
        let gauges = app.instrument.courses.map { $0.strings.first?.gauge }
        return Self.sets(for: app.instrument).first { $0.1.map(Optional.some) == gauges.reversed().map { $0 } || $0.1.map(Optional.some) == gauges }?.0
    }

    private func apply(_ gauges: [Double]) {
        app.updateInstrument { inst in
            // gauges listed from the lowest string
            for (c, g) in zip(inst.courses.indices, gauges) { for s in inst.courses[c].strings.indices { inst.courses[c].strings[s].gauge = g } }
        }
    }

    /// Common sets, from the lowest string.
    static func sets(for i: Instrument) -> [(String, [Double])] {
        switch (i.type, i.courses.count) {
        case (.guitar, 6), (.guitarExtendedHigh, 6):
            return [("D'Addario 10–46", [0.046, 0.036, 0.026, 0.017, 0.013, 0.010]), ("D'Addario 11–49", [0.049, 0.038, 0.028, 0.018, 0.014, 0.011])]
        case (.guitar, 7), (.guitarExtendedHigh, 7):
            return [("D'Addario 10–59", [0.059, 0.046, 0.036, 0.026, 0.017, 0.013, 0.010])]
        case (.guitar, 8), (.guitarExtendedHigh, 8):
            return [("D'Addario 10–74", [0.074, 0.062, 0.052, 0.042, 0.030, 0.017, 0.013, 0.010])]
        case (.guitar, 9), (.guitarExtendedHigh, 9):
            return [("Kalium 9-str 10–90", [0.090, 0.072, 0.059, 0.049, 0.038, 0.028, 0.017, 0.013, 0.010])]
        case (.bass, 4): return [("D'Addario 45–105", [0.105, 0.085, 0.065, 0.045])]
        case (.bass, 5): return [("D'Addario 45–130", [0.130, 0.105, 0.085, 0.065, 0.045])]
        default: return []
        }
    }
}
