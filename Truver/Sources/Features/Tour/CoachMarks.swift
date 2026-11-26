import SwiftUI

// Coach marks of the canvas «Знакомство и обучение» (CoachTuner1–3, CoachFret1–3, CoachTab, CoachChord, CoachMetro1–2,
// CoachPractice). One to three hints the first time a section or a feature opens: the screen dims (#030304 at 74 %)
// except a hole around the element, a 2 pt ivory ring 4 pt outside the hole, and an ivory bubble with an arrow.
//
// Behaviour (canvas note «Знакомство»): only when the section is opened for the first time; not while the tuner hears
// a note or the metronome plays; «Пропустить» turns off the hints of this section; repeat: Settings → «Обучение».
// Hints are armed by finishing the first-run onboarding (or «Показать подсказки заново»), so screenshot launches
// (`-skipOnboarding`) never show them; `-coach tuner1…` shows one directly.

/// Sections with hints, in the order of the canvas note.
enum CoachSection: String, CaseIterable {
    case tuner, fret, tab, chord, metro, practice
}

/// One hint. The hole is the union of the anchors' frames grown by `outset` (canvas values: the boards place the hole
/// by hand, a few points off the element on some boards). The bubble sits `gap` above or below the hole.
struct CoachStep {
    let title: String
    let text: String
    let anchors: [String]
    /// Hole corner radius (CSS `border-radius`; ≥ half the side — a circle).
    let radius: CGFloat
    var outset = EdgeInsets()
    /// Bubble under the hole (arrow up) or above it (arrow down).
    let below: Bool
    let gap: CGFloat
}

enum CoachCatalog {
    /// Anchor ids set by the screens with `.coachAnchor(_:)`.
    enum Anchor {
        static let tunerStrings = "tuner.strings"
        static let tunerReference = "tuner.reference"
        static let tunerMore = "tuner.more"
        static let tuningPill = "shell.tuningPill"
        static let scalePill = "fret.scalePill"
        static let firstTonic = "fret.firstTonic"
        static let keyChords = "fret.keyChords"
        static let tabSystem = "fret.tabSystem"
        static let voicingPrev = "fret.voicingPrev"
        static let voicingNext = "fret.voicingNext"
        static let knob = "metro.knob"
        static let chips = "metro.chips"
        static let trainer = "practice.trainer"
    }

    // Gaps: the canvas bubble's edge to the hole's edge (bubble height = 16 + 20.57 + 6 + lines × 20.3 + 14 + 38 + 14).
    static func steps(_ section: CoachSection) -> [CoachStep] {
        switch section {
        case .tuner:
            return [
                CoachStep(title: "Тюнер сам узнаёт струну",
                          text: "Просто играйте. Если мешает шум или соседние струны — нажмите нужную струну здесь, и тюнер будет слушать только её",
                          anchors: [Anchor.tunerStrings], radius: 14, below: false, gap: 12.5),
                CoachStep(title: "Настроить на слух",
                          text: "Волна — Truver сыграет ноту выбранной струны. Кнопка рядом — строб для очень точной подстройки и крупный сценический экран",
                          anchors: [Anchor.tunerReference, Anchor.tunerMore], radius: 26,
                          outset: EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 6), below: false, gap: 10.2),
                // Canvas hole 210 × 48 is narrower than the pill (it cuts both ends): the hole hugs the pill instead; the bubble
                // stays where the canvas has it (gap 24.5 + 4).
                CoachStep(title: "Строй и инструмент — здесь",
                          text: "Drop D, полтона ниже, свой строй или другой инструмент. Выбранный строй сразу применится к грифу",
                          anchors: [Anchor.tuningPill], radius: 24,
                          outset: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4), below: false, gap: 28.5),
            ]
        case .fret:
            return [
                CoachStep(title: "Выберите гамму",
                          text: "Тонику и вид гаммы. Жёлтые точки — тоника, синие — ноты аккорда, кружки — остальные ноты гаммы",
                          anchors: [Anchor.scalePill], radius: 20,
                          outset: EdgeInsets(top: 3, leading: 0, bottom: 1, trailing: 4), below: true, gap: 24),
                CoachStep(title: "Нажмите на ноту",
                          text: "Откроется меню: гамма, аккорды или прогрессия от этой ноты. Гриф листается вверх и вниз до 24-го лада",
                          anchors: [Anchor.firstTonic], radius: 30,
                          outset: EdgeInsets(top: 18, leading: 19, bottom: 16, trailing: 15), below: true, gap: 30),
                // Canvas hole 606…662 sits 12 pt above the chord strip (618…670) and cuts it: the hole hugs the strip.
                CoachStep(title: "Аккорды этой гаммы",
                          text: "Нажмите аккорд — его ноты подсветятся на грифе. Римские цифры — ступень: I, IV и V звучат вместе лучше всего",
                          anchors: [Anchor.keyChords], radius: 14,
                          outset: EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0), below: false, gap: 42.5),
            ]
        case .tab:
            return [
                CoachStep(title: "Как читать табулатуру",
                          text: "Линии — струны, нижняя — самая толстая. Цифра — какой лад зажать, 0 — открытая струна. Играйте слева направо",
                          anchors: [Anchor.tabSystem], radius: 14, outset: EdgeInsets(top: 94, leading: 0, bottom: -22, trailing: 0), below: true, gap: 21),
            ]
        case .chord:
            return [
                CoachStep(title: "Этот же аккорд в другом месте",
                          text: "Стрелками — другие расположения на грифе. Сначала самые простые, дальше — с баррэ и растяжкой",
                          anchors: [Anchor.voicingPrev, Anchor.voicingNext], radius: 26,
                          outset: EdgeInsets(top: 6, leading: 0, bottom: 2, trailing: 4), below: false, gap: 22.5),
            ]
        case .metro:
            return [
                CoachStep(title: "Темп — ручкой",
                          text: "Ведите пальцем по кругу: по часовой — быстрее. Или простучите ритм на кнопке «Тап» внизу",
                          anchors: [Anchor.knob], radius: 1000,
                          outset: EdgeInsets(top: -10, leading: -10, bottom: -10, trailing: -10), below: true, gap: 30),
                CoachStep(title: "Размер и режимы",
                          text: "7/8, деление доли, разгон и пропуски — здесь. «Проверка» слушает вашу игру и показывает, где вы спешите. Всё вместе сохраняется в пресет",
                          anchors: [Anchor.chips], radius: 24,
                          outset: EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0), below: true, gap: 16),
            ]
        case .practice:
            return [
                CoachStep(title: "Выучите ноты на грифе",
                          text: "Тренажёр показывает место на грифе — вы называете ноту или играете её. Начните с ладов 1–5 и расширяйте, когда станет легко",
                          anchors: [Anchor.trainer], radius: 16,
                          outset: EdgeInsets(top: 4, leading: 0, bottom: -2, trailing: 0), below: true, gap: 18),
            ]
        }
    }

    /// `-coach tuner1 | tuner2 | tuner3 | fret1…3 | tab | chord | metro1 | metro2 | practice` (canvas board names).
    static func parse(_ value: String) -> (CoachSection, Int)? {
        for section in CoachSection.allCases where value.hasPrefix(section.rawValue) {
            let rest = value.dropFirst(section.rawValue.count)
            if rest.isEmpty { return (section, 0) }
            if let n = Int(rest), n >= 1, n <= steps(section).count { return (section, n - 1) }
        }
        return nil
    }
}

/// Hints state: anchors reported by the screens, the running hint, and what has been seen (UserDefaults).
@MainActor
@Observable
final class CoachCenter {
    static let shared = CoachCenter()

    /// Frames of the anchors in the window (global) coordinates.
    var anchors: [String: CGRect] = [:]

    struct Run: Equatable {
        let section: CoachSection
        /// Indices of the catalog steps shown (steps whose anchor is missing on this layout are left out).
        let steps: [Int]
        var position: Int
        /// Launched by `-coach`: nothing is saved.
        let debug: Bool
    }

    private(set) var run: Run?

    /// «Подсказки на экранах».
    var enabled: Bool { didSet { defaults.set(enabled, forKey: Keys.enabled) } }
    /// Hints start only after the first-run onboarding (or «Показать подсказки заново»).
    private(set) var armed: Bool
    private(set) var seen: Set<String>
    /// `-coach <board>`: the section and step to show at launch.
    private(set) var forced: (CoachSection, Int)?

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let enabled = "coach.enabled", armed = "coach.armed", seen = "coach.seen"
    }

    private init() {
        enabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        armed = defaults.bool(forKey: Keys.armed)
        seen = Set(defaults.stringArray(forKey: Keys.seen) ?? [])
        let arguments = ProcessInfo.processInfo.arguments
        if let i = arguments.firstIndex(of: "-coach"), i + 1 < arguments.count { forced = CoachCatalog.parse(arguments[i + 1]) }
    }

    func wants(_ section: CoachSection) -> Bool { armed && enabled && !seen.contains(section.rawValue) }

    /// Onboarding finished / «Показать подсказки заново»: every section shows its hints again.
    func arm() {
        armed = true
        enabled = true
        seen = []
        defaults.set(true, forKey: Keys.armed)
        defaults.set([String](), forKey: Keys.seen)
    }

    func frame(of step: CoachStep) -> CGRect? {
        let rects = step.anchors.compactMap { anchors[$0] }.filter { $0.width > 0 && $0.height > 0 }
        guard rects.count == step.anchors.count, var r = rects.first else { return nil }
        for other in rects.dropFirst() { r = r.union(other) }
        return CGRect(x: r.minX - step.outset.leading, y: r.minY - step.outset.top,
                      width: r.width + step.outset.leading + step.outset.trailing,
                      height: r.height + step.outset.top + step.outset.bottom)
    }

    /// Starts the section's hints with the steps whose anchors are on screen; false when none is.
    @discardableResult
    func start(_ section: CoachSection, at step: Int = 0, debug: Bool = false) -> Bool {
        let all = CoachCatalog.steps(section)
        let shown = all.indices.filter { debug || frame(of: all[$0]) != nil }
        guard !shown.isEmpty else { return false }
        #if DEBUG
        if debug { for (k, v) in anchors.sorted(by: { $0.key < $1.key }) { print("COACH anchor", k, v.minX, v.minY, v.width, v.height) } }
        #endif
        run = Run(section: section, steps: shown, position: max(0, min(shown.count - 1, shown.firstIndex(of: step) ?? 0)), debug: debug)
        return true
    }

    func next() {
        guard var r = run else { return }
        if r.position + 1 < r.steps.count {
            r.position += 1
            run = r
        } else {
            finish()
        }
    }

    /// «Понятно» on the last step or «Пропустить»: the section is done.
    func finish() {
        guard let r = run else { return }
        if !r.debug {
            seen.insert(r.section.rawValue)
            defaults.set(Array(seen), forKey: Keys.seen)
        }
        run = nil
    }

    func consumeForced() -> (CoachSection, Int)? {
        defer { forced = nil }
        return forced
    }
}

extension View {
    /// Reports this view's frame for the coach marks (`CoachCatalog.Anchor`). nil — no anchor.
    func coachAnchor(_ id: String?) -> some View { modifier(CoachAnchorModifier(id: id)) }
}

private struct CoachAnchorModifier: ViewModifier {
    let id: String?

    func body(content: Content) -> some View {
        if let id {
            content
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { CoachCenter.shared.anchors[id] = $0 }
                .onDisappear { CoachCenter.shared.anchors[id] = nil }
        } else {
            content
        }
    }
}

// MARK: Host

/// Watches the app and shows the hints over everything (TruverApp overlay).
struct CoachHost: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var center: CoachCenter { CoachCenter.shared }

    /// The section whose hints the current screen offers now (nil — none, or not now).
    private var candidate: CoachSection? {
        guard center.run == nil, !app.showOnboarding, !app.showSettings, !app.showSession, !app.showTrainer,
              app.sheet == nil, app.notice == nil else { return nil }
        let section: CoachSection?
        switch app.settings.lastTab {
        case .tuner:
            // «Не показываются, пока идёт настройка»: wait until the tuner hears nothing.
            if case .reading = app.tuner.display { section = nil } else { section = .tuner }
        case .fretboard:
            let f = app.fretboard
            if f.showsTabScreen { section = .tab }
            else if f.mode == .chord { section = .chord }
            else if f.mode == .scale && f.noteSpot == nil && f.pathKind == nil && !f.isTraining { section = .fret }
            else { section = nil }
        case .metronome:
            section = app.metronome.isPlaying ? nil : .metro
        case .practice:
            section = .practice
        }
        guard let section, center.wants(section) else { return nil }
        return section
    }

    var body: some View {
        ZStack {
            if let run = center.run {
                CoachOverlay(run: run)
                    .transition(.opacity)
            }
        }
        .animation(Motion.out(Motion.Duration.base), value: center.run?.section)
        .task(id: candidate) {
            guard let section = candidate else { return }
            // The screen settles (tab switch, layout) and the person looks at it first.
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled, candidate == section else { return }
            center.start(section)
        }
        .task {
            guard let (section, step) = center.forced else { return }
            // Screenshot hook: wait for the anchors of the board's screen (sheets, demo states set up first).
            for _ in 0..<40 {
                if CoachCatalog.steps(section).indices.contains(step), center.frame(of: CoachCatalog.steps(section)[step]) != nil { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            _ = center.consumeForced()
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { _ = center.start(section, at: step, debug: true) }
        }
    }
}

/// Canvas colours of the hints (only here).
enum CoachColors {
    static let dim = Color(hex: 0x030304, opacity: 0.74)
    static let ring = Color(hex: 0xf6f3ec, opacity: 0.7)
    static let bubble = Color(hex: 0xf6f3ec)
    static let ink = Color(hex: 0x0c0d0f)
    static let text = Color(hex: 0x3a3b3f)
    static let counter = Color(hex: 0x6b6c70)
}

/// The dim with a hole, the ring and the bubble.
private struct CoachOverlay: View {
    let run: CoachCenter.Run
    @Environment(\.dynamicTypeSize) private var typeSize
    private var center: CoachCenter { CoachCenter.shared }

    var body: some View {
        let all = CoachCatalog.steps(run.section)
        let step = all[run.steps[run.position]]
        GeometryReader { proxy in
            let size = proxy.size
            let hole = center.frame(of: step) ?? CGRect(x: size.width / 2, y: size.height / 2, width: 0, height: 0)
            let radius = min(step.radius, hole.width / 2, hole.height / 2)
            ZStack(alignment: .topLeading) {
                CoachDim(hole: hole, radius: radius)
                    .fill(CoachColors.dim, style: FillStyle(eoFill: true))
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    .accessibilityHidden(true)
                // CSS `outline: 2px; outline-offset: 4px` follows the radius: 4…6 pt outside the hole.
                RoundedRectangle(cornerRadius: radius + 5, style: .circular)
                    .stroke(CoachColors.ring, lineWidth: 2)
                    .frame(width: hole.width + 10, height: hole.height + 10)
                    .offset(x: hole.minX - 5, y: hole.minY - 5)
                    .allowsHitTesting(false)
                bubble(step, hole: hole, width: size.width - 40)
                    .id(run.steps[run.position])
                    .transition(.opacity)
            }
            .animation(Motion.out(Motion.Duration.base), value: run.position)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder private func bubble(_ step: CoachStep, hole: CGRect, width: CGFloat) -> some View {
        // Canvas: the arrow's centre is 20 pt right of the hole's centre on every board.
        let arrowX = min(max(hole.midX + 20 - 20, 24), width - 24)
        let content = CoachBubble(step: step, run: run, width: width, arrowX: arrowX, arrowUp: step.below)
        if step.below {
            content.offset(x: 20, y: hole.maxY + step.gap)
        } else {
            content
                .frame(width: width, height: max(0, hole.minY - step.gap), alignment: .bottom)
                .offset(x: 20)
        }
    }
}

/// Everything but the hole (even-odd).
private struct CoachDim: Shape {
    var hole: CGRect
    var radius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat>> {
        get { AnimatablePair(AnimatablePair(hole.minX, hole.minY), AnimatablePair(AnimatablePair(hole.width, hole.height), radius)) }
        set {
            hole = CGRect(x: newValue.first.first, y: newValue.first.second, width: newValue.second.first.first, height: newValue.second.first.second)
            radius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path(rect.insetBy(dx: -40, dy: -40))
        p.addRoundedRect(in: hole, cornerSize: CGSize(width: radius, height: radius), style: .circular)
        return p
    }
}

/// Canvas bubble: 350 wide, padding 16 16 14, radius 18, #f6f3ec, shadow `0 20px 50px` black 60 %; the arrow — a
/// 14 pt square turned 45° on the edge. Title 17 semibold, text 14 / 1.45 (6 below the title), footer 14 below:
/// «1 из 3» 13, «Пропустить» underlined (14 apart, padding 8), the dark 38 pt button.
private struct CoachBubble: View {
    let step: CoachStep
    let run: CoachCenter.Run
    let width: CGFloat
    let arrowX: CGFloat
    let arrowUp: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    private var center: CoachCenter { CoachCenter.shared }

    var body: some View {
        let last = run.position == run.steps.count - 1
        let multi = run.steps.count > 1
        VStack(alignment: .leading, spacing: 0) {
            Text(step.title).font(Typo.inter(17, .semibold)).foregroundStyle(CoachColors.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(typeSize == .large ? TunerScreen.greedyLines(step.text, font: Typo.Weight.regular.rawValue, size: 14, width: width - 32) : step.text)
                .font(Typo.inter(14)).foregroundStyle(CoachColors.text)
                .lineSpacing(14 * 1.45 - 14 * 1.2109)
                .padding(.vertical, (14 * 1.45 - 14 * 1.2109) / 2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            HStack(spacing: 0) {
                if multi {
                    Text("\(run.position + 1) из \(run.steps.count)").font(Typo.inter(13)).foregroundStyle(CoachColors.counter)
                    Button { center.finish() } label: {
                        Text("Пропустить").font(Typo.inter(13)).underline().foregroundStyle(CoachColors.text)
                            .padding(.horizontal, 8).padding(.vertical, 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, -12)
                    .padding(.leading, 14)
                }
                Spacer(minLength: 8)
                Button { if last { center.finish() } else { center.next() } } label: {
                    Text(last ? "Понятно" : "Дальше").font(Typo.inter(14, .semibold)).foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 18)
                        .frame(height: 38)
                        .background(Capsule(style: .circular).fill(CoachColors.ink))
                }
                .buttonStyle(PressableStyle())
            }
            .frame(height: 38)
            .padding(.top, 14)
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 14)
        .frame(width: width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .circular).fill(CoachColors.bubble)
            .shadow(color: .black.opacity(0.6), radius: 25, y: 20))
        .overlay(alignment: arrowUp ? .topLeading : .bottomLeading) {
            Rectangle().fill(CoachColors.bubble).frame(width: 14, height: 14).rotationEffect(.degrees(45))
                .offset(x: arrowX - 7, y: arrowUp ? -7 : 7)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

// MARK: Fretboard helpers

extension CoachCatalog {
    /// «Нажмите на ноту»: the tonic nearest the nut on the lowest string that has one (canvas: G on the 8th string, 1st fret).
    static func firstTonic(_ cells: [NeckCell]) -> NeckSpot? {
        cells.filter { $0.role == .tonic && $0.fret >= 1 && $0.fret <= 12 }
            .min { ($0.fret, $0.course) < ($1.fret, $1.course) }
            .map { NeckSpot(course: $0.course, fret: $0.fret) }
    }
}

extension NeckPortrait {
    /// The note that reports its frame for the coach mark.
    func coaching(_ spot: NeckSpot?) -> NeckPortrait {
        var copy = self
        copy.coachCell = spot
        return copy
    }
}
