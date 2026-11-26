import SwiftUI
import TruverTheory

/// «Гриф и гаммы» by the canvas (390 × 844): scale chip + «Вид и подписи» (top 100), neck 346 × 396 (top 156),
/// key chords (top 566, 52 pt), position navigation and «Сыграть» (top 626, 52 pt).
struct FretboardScreen: View {
    @Environment(AppModel.self) private var app
    @State private var zoom: CGFloat = 1
    @State private var pinchBase: CGFloat = 1
    @State private var showZoom = false
    @State private var zoomTask: Task<Void, Never>?
    @State private var editingWindow = false
    @State private var menuPoint: CGPoint?
    /// FB-20: the neck follows the current path note until the user scrolls it.
    @State private var autoScroll = true
    @State private var showLibrary = false
    /// «Гаммы ›» opens the library scrolled to «Подходящие гаммы».
    @State private var libraryAtScales = false
    @State private var namingProgression = false
    @State private var renamingProgression = false
    @State private var progressionName = ""
    /// Frets on screen while the custom window is edited.
    @State private var windowContext: ClosedRange<Int>?

    private var fretboard: FretboardController { app.fretboard }

    @Environment(\.isPhoneLandscape) private var phoneLandscape

    var body: some View {
        if phoneLandscape {
            // «Таб» (fork «T», FretTabView.swift): the path as a tablature instead of the neck.
            if fretboard.showsTabScreen { FretTabLandscape() } else { landscapeBoard }
        } else if fretboard.showsTabScreen {
            FretTabScreen()
        } else {
            GeometryReader { proxy in
                #if os(macOS)
                if proxy.size.width > proxy.size.height { landscape } else { portrait }
                #else
                portrait
                #endif
            }
        }
    }

    // MARK: Portrait (canvas 2026-11-25: «Гриф — 6/7/8 струн», FixFretWhole, капо, левша)

    private var modeBinding: Binding<FretMode> {
        Binding(get: { fretboard.mode }, set: { value in
            // «Гамма» while on the path leaves the path (iPhone UX check: it stayed in «· путь»).
            if fretboard.pathKind != nil && (value == .scale || value != fretboard.mode) {
                if fretboard.isPlaying { fretboard.stopPlayback() }
                if value == .scale { fretboard.pathKind = nil }
            }
            fretboard.mode = value
        })
    }

    private var portrait: some View {
        VStack(spacing: 0) {
            // Canvas FretLeftHanded keeps the title; the mirror is announced by a notice.
            ScreenHeader(title: "Гриф и гаммы", subtitle: app.title)
            // Canvas: the mode segments at 108, 14 below the 44 pt header row.
            Segments(options: [(FretMode.scale, "Гамма"), (.chord, "Аккорд"), (.search, "Поиск"), (.progression, "Прогрессия")],
                     selection: modeBinding)
                .padding(.horizontal, 20).padding(.top, 14)
            switch fretboard.mode {
            case .scale:
                if fretboard.isTraining || fretboard.pathKind != nil || editingWindow { legacyScale } else { canvasScale }
            case .chord:
                // Canvas FretChordTab: chips at 154, neck 400 at 200, «Am7 · баррэ на 5-м» + ‹ › at 622.
                chordChips.frame(height: 34).padding(.horizontal, 20).padding(.top, 8)
                modeNeck(sizing: .large).padding(.top, 12)
                chordFooter.padding(.horizontal, 20).padding(.top, 22)
            case .search:
                // Canvas FixFretSearch: «Отмечено 4 ноты ▾» row, neck 400 at 206 (the result is a sheet).
                HStack(spacing: 8) {
                    pickerPill(searchTitle) { app.sheet = .searchResults }
                    neckTabSwitch
                    RoundIconButton(icon: .rename, size: 36, label: "Вид и подписи") { app.sheet = .fretView }
                }
                .frame(height: 38).padding(.horizontal, 20).padding(.top, 8)
                modeNeck(sizing: .large).padding(.top, 14)
            case .progression:
                // Canvas FlowNote3: «A · I–V–vi–IV ▾» row, neck 400 at 204, chords 56 at 616, footer at 686.
                HStack(spacing: 8) {
                    pickerPill(progressionTitle) { app.sheet = .fretProgressions }
                    neckTabSwitch
                    RoundIconButton(icon: .rename, size: 36, label: "Вид и подписи") { app.sheet = .fretView }
                }
                .frame(height: 38).padding(.horizontal, 20).padding(.top, 8)
                if fretboard.tabView {
                    // Fork «T»: the progression as a chord tablature (FlowNote3Tab).
                    progressionTab
                } else {
                    modeNeck(sizing: .progression).padding(.top, 12)
                    progressionChords.padding(.horizontal, 20).padding(.top, 12)
                    progressionFooter.padding(.horizontal, 20).padding(.top, 14)
                }
            }
            Spacer(minLength: 0)
        }
        .coordinateSpace(name: "fretScreen")
        #if DEBUG
        .onAppear { if ProcessInfo.processInfo.arguments.contains("-chordLibrary") { showLibrary = true } }
        #endif
        .overlay(alignment: .topLeading) { noteMenu }
        .overlay {
            if namingProgression {
                TextFieldAlert(title: "Название прогрессии", text: $progressionName, cancel: { namingProgression = false }, save: {
                    if renamingProgression { fretboard.progression.renameActive(progressionName) } else { fretboard.progression.saveAs(progressionName) }
                    namingProgression = false
                })
            }
        }
        .overlay { if showLibrary { ChordLibraryView(atScales: libraryAtScales) { showLibrary = false }.transition(.move(edge: .trailing)) } }
        .animation(Motion.out(Motion.Duration.base), value: showLibrary)
        .animation(Motion.out(Motion.Duration.quick), value: fretboard.mode)
        .overlay(alignment: .top) {
            if let toast = fretboard.toast {
                DesignToast(icon: .refresh, text: toast).padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Motion.out(Motion.Duration.base), value: fretboard.toast)
        .overlay(alignment: .top) {
            if let capoNotice { capoNoticeView(capoNotice).padding(.top, 640 - 47).transition(.opacity).allowsHitTesting(false) }
        }
        .overlay(alignment: .topLeading) { loupe }
        .overlay(alignment: .bottom) {
            if let spot = fretboard.noteSpot, fretboard.mode == .scale, !(fretboard.isTraining || fretboard.pathKind != nil || editingWindow) {
                notePanel(spot)
            }
        }
        .onChange(of: app.instrument.capo) { _, capo in showCapoNotice(capo) }
        .onChange(of: fretboard.settings.leftHanded) { _, left in if left { showNotice("Для левши: низкая струна справа") } }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-capo") { showCapoNotice(app.instrument.capo) }
            if ProcessInfo.processInfo.arguments.contains("-leftHanded") { showNotice("Для левши: низкая струна справа", hold: true) }
            if let spot = fretboard.debugScrub {
                // The cell's centre on the scrolling neck at the top (board at 42, 252; 1–12 in 356 pt).
                let g = NeckPortrait.Geometry(size: CGSize(width: ScrollingNeck.boardWidth, height: 1), courses: app.instrument.courses.count,
                                              frets: 0...1, leftHanded: fretboard.settings.leftHanded)
                let scale = 357 / NeckPortrait.unit(12)
                let y = 252 + scale * (NeckPortrait.unit(spot.fret - 1) + NeckPortrait.unit(spot.fret)) / 2 - 1
                scrub = (spot, CGPoint(x: (fretboard.settings.leftHanded ? 18 : 22) + 20 + g.x(course: spot.course), y: y - 47))
            }
        }
    }

    /// Path, training and the custom window keep the previous layout (no canvas boards for them in Гриф view).
    @ViewBuilder private var legacyScale: some View {
        Group { if editingWindow { windowBar } else { scaleRow } }
            .padding(.horizontal, 20).padding(.top, 10)
        neck.padding(.horizontal, 22).padding(.top, 12)
        if fretboard.isTraining {
            trainingBar.padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 10)
        } else if fretboard.pathKind != nil {
            pathBar.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 10)
        } else {
            chordStrip.padding(.horizontal, 20).padding(.top, 14)
            navigation.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 10)
        }
    }

    /// Canvas «Гамма»: row at 154 (pill 36, «Гриф | Таб» 120, «Вид и подписи» 36), legend at 202, neck block 386 at 222
    /// (open strings 30 + scrolling neck 356), key chords at 618, «Лады 1–12 из 24» + «Сыграть» at 680.
    @ViewBuilder private var canvasScale: some View {
        HStack(spacing: 8) {
            pickerPill(scalePillTitle, edited: fretboard.isEdited) { app.sheet = .fretScale }
                .accessibilityLabel("Гамма: \(scaleTitle)")
                .coachAnchor(CoachCatalog.Anchor.scalePill)
            neckTabSwitch
            RoundIconButton(icon: .rename, size: 36, label: "Вид и подписи") { app.sheet = .fretView }
        }
        .frame(height: 38)
        .padding(.horizontal, 20).padding(.top, 8)
        if fretboard.noteSpot != nil {
            // Canvas FlowNote1: no legend, the neck at 200 (30 + 370), the note panel over the tab bar (overlay).
            wholeNeck(height: 370, sizing: .allNotes).padding(.top, 8)
        } else {
            // Canvas S8Loupe: the legend steps aside for the loupe.
            legend.frame(maxWidth: .infinity, minHeight: 20, maxHeight: 20, alignment: .topLeading)
                .opacity(scrub == nil ? 1 : 0)
                .padding(.horizontal, 20).padding(.top, 10)
            wholeNeck(height: 356, sizing: .scale)
            chordStrip.coachAnchor(CoachCatalog.Anchor.keyChords).padding(.horizontal, 20).padding(.top, 10)
            Group { if let scrub { scrubFooter(scrub.spot) } else { scaleFooter } }
                .padding(.horizontal, 20).padding(.top, 10)
        }
    }

    /// Canvas FlowNote1 panel (top 610 to the bottom, #141518, r 26): handle 40 × 5, the note 44 ivory, «A2 · 6-я струна,
    /// 5-й лад» 17 semibold / «что построить от этой ноты?», ▶ 36; «Гамма», «Аккорды», «Прогрессия» 44 pt.
    private func notePanel(_ spot: NeckSpot) -> some View {
        let pitch = fretboard.fretboard?.pitch(course: spot.course, fret: spot.fret)
        let name = pitch.map { app.chromaticName($0) } ?? ""
        let letter = name.filter { !$0.isNumber }
        let string = app.instrument.courses.count - spot.course
        let place = spot.fret == 0 ? "открытая" : "\(spot.fret)-й лад"
        // CSS `flex: 1` with `white-space: nowrap`: a label wider than the share keeps its width (padding 18).
        func button(_ title: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Text(title).font(Typo.inter(14, primary ? .semibold : .medium))
                    .foregroundStyle(primary ? Theme.background : Theme.textBody)
                    .lineLimit(1).fixedSize()
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(Capsule().fill(primary ? AnyShapeStyle(Theme.primaryFill) : AnyShapeStyle(Theme.cardFill)))
                    .overlay(Capsule().strokeBorder(primary ? Color.clear : Theme.hairline, lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
        }
        return VStack(spacing: 0) {
            Capsule().fill(Color.white.opacity(0.2)).frame(width: 40, height: 5).padding(.top, 8)
            HStack(spacing: 12) {
                Typo.notes(letter, size: 18, weight: .bold, fixed: true).foregroundStyle(Color(hex: 0x0c0d0f))
                    .frame(width: 44, height: 44).background(Circle().fill(Theme.textPrimary))
                VStack(alignment: .leading, spacing: 2) {
                    Typo.notes("\(name) · \(string)-я струна, \(place)", size: 17, weight: .semibold).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Text("что построить от этой ноты?").font(Typo.caption).foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                RoundIconButton(icon: .play, size: 36, iconSize: 14, label: "Сыграть ноту") { fretboard.tap(course: spot.course, fret: spot.fret) }
            }
            .padding(.horizontal, 20).padding(.top, 10)
            HStack(spacing: 8) {
                button("Гамма") { app.sheet = .scaleFromNote(spot.course, spot.fret) }
                button("Аккорды") { app.sheet = .chordsFromNote(spot.course, spot.fret) }
                button("Прогрессия", primary: true) { app.sheet = .progressionFromNote(spot.course, spot.fret) }
            }
            .padding(.horizontal, 20).padding(.top, 14)
            Spacer(minLength: 0)
        }
        .frame(height: 234 - 34, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26)
                .fill(Theme.panel)
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26).stroke(Color.white.opacity(0.08), lineWidth: 1).mask(alignment: .top) { Rectangle().frame(height: 26) })
                .shadow(color: .black.opacity(0.6), radius: 20, y: -20)
                .ignoresSafeArea(edges: .bottom)
        }
        .gesture(DragGesture(minimumDistance: 10).onEnded { v in if v.translation.height > 40 { fretboard.noteSpot = nil } })
        .transition(.move(edge: .bottom))
    }

    /// «G · Мажор» — the pill drops the scale's parenthesised alias («Мажор (ионийский)»).
    private var scalePillTitle: String {
        let name = fretboard.scaleTitle
        let short = name.range(of: " (").map { String(name[..<$0.lowerBound]) } ?? name
        return short   // canvas FretCapo: the capo is on the neck and in a notice, not in the title
    }

    @State private var capoNotice: String?
    /// Canvas S8Loupe: the cell under a held finger and its centre.
    @State private var scrub: (spot: NeckSpot, point: CGPoint)?

    /// Canvas S8Loupe: a 46 pt ring under the finger and a 200 × 150 loupe (r 22, #2b2f36, 2 pt ivory .7 border) 220 pt
    /// above it: three strings 70 apart with their open names, two frets 46 apart with numbers, the note 44 ivory.
    @ViewBuilder private var loupe: some View {
        if let scrub {
            let courses = app.instrument.courses.count
            let c = scrub.spot.course, f = scrub.spot.fret
            let name = { (course: Int) in app.stringName(StringRef(course: course)).filter { !$0.isNumber } }
            let pitch = fretboard.fretboard?.pitch(course: c, fret: f)
            ZStack(alignment: .topLeading) {
                Circle().fill(Theme.textPrimary.opacity(0.18)).overlay(Circle().strokeBorder(Theme.textPrimary.opacity(0.5), lineWidth: 2))
                    .frame(width: 46, height: 46)
                    .position(scrub.point)
                ZStack(alignment: .topLeading) {
                    Color(hex: 0x2b2f36)
                    ForEach([-1, 0, 1], id: \.self) { d in
                        let course = c + d
                        if course >= 0 && course < courses {
                            let x: CGFloat = [31, 100.5, 170.5][d + 1]
                            Rectangle().fill(LinearGradient(colors: [Color(hex: 0x7d8186), Color(hex: 0xe6e8ea), Color(hex: 0x7d8186)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: d < 0 ? 4 : 3, height: 122).offset(x: x - (d < 0 ? 2 : 1.5), y: 14)
                            Typo.notes(name(course), size: 11).foregroundStyle(Theme.textSecondary)
                                .frame(width: 20).offset(x: x - 10, y: -2)
                        }
                    }
                    ForEach(0..<3, id: \.self) { i in
                        Rectangle().fill(LinearGradient(colors: [Color(hex: 0x6f7378), .white, Color(hex: 0x55595e)], startPoint: .top, endPoint: .bottom))
                            .frame(width: 184, height: 3).offset(x: 6, y: 20 + CGFloat(i) * 46)
                        if i < 2 {
                            Text("\(max(1, f) + i)").font(Typo.inter(10)).foregroundStyle(Theme.textTertiary).offset(x: 6, y: 36 + CGFloat(i) * 46)
                        }
                    }
                    Typo.notes(pitch.map { app.chromaticName($0).filter { !$0.isNumber } } ?? "", size: 16, weight: .bold, fixed: true)
                        .foregroundStyle(Color(hex: 0x0c0d0f))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Theme.textPrimary))
                        .background(Circle().stroke(Theme.textPrimary.opacity(0.25), lineWidth: 8).frame(width: 44, height: 44))
                        .offset(x: 78, y: 21)
                }
                .frame(width: 200, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.textPrimary.opacity(0.7), lineWidth: 2))
                .shadow(color: .black.opacity(0.7), radius: 20, y: 20)
                .offset(x: min(max(16, scrub.point.x - 100), 390 - 216), y: scrub.point.y - 220)
            }
            .allowsHitTesting(false)
        }
    }

    /// «D3 · 4-я струна (A), 5-й лад» / «ведите палец — лупа следует, отпустите — нота поставлена».
    private func scrubFooter(_ spot: NeckSpot) -> some View {
        let pitch = fretboard.fretboard?.pitch(course: spot.course, fret: spot.fret)
        let open = app.stringName(StringRef(course: spot.course)).filter { !$0.isNumber }
        let place = spot.fret == 0 ? "открытая" : "\(spot.fret)-й лад"
        return VStack(alignment: .leading, spacing: 3) {
            Typo.notes("\(pitch.map { app.chromaticName($0) } ?? "") · \(app.instrument.courses.count - spot.course)-я струна (\(open)), \(place)", size: 14, weight: .medium)
                .foregroundStyle(Theme.textPrimary).lineLimit(1)
            Text("ведите палец — лупа следует, отпустите — нота поставлена").font(Typo.caption).foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
    }

    /// Canvas FretCapo notice (left 24, right 24, top 640): #26282d .96, r 16, hairline, 13 medium, padding 11 16.
    private func showCapoNotice(_ capo: Int) {
        guard capo > 0 else { return }
        showNotice("Капо на \(capo)-м ладу · ноты и номера ладов — от капо", hold: ProcessInfo.processInfo.arguments.contains("-capo"))
    }

    /// Canvas FretCapo / FretLeftHanded notice at 640 for 3 s (held in screenshots).
    private func showNotice(_ text: String, hold: Bool = false) {
        withAnimation(Motion.out(Motion.Duration.base)) { capoNotice = text }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(hold ? 30 : 3))
            guard capoNotice == text else { return }
            withAnimation(Motion.out(Motion.Duration.base)) { capoNotice = nil }
        }
    }

    private func capoNoticeView(_ text: String) -> some View {
        Text(text).font(Typo.inter(13, .medium)).foregroundStyle(Theme.textBody)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(red: 38 / 255, green: 40 / 255, blue: 45 / 255, opacity: 0.96)))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairlineStrong, lineWidth: 1))
            .shadow(color: .black.opacity(0.6), radius: 15, y: 14)
            .padding(.horizontal, 24)
    }

    /// Canvas pill: 36 pt, radius 18, card fill + hairline, 14 medium, chevron 14 tertiary; padding 0 12 0 14, gap 6.
    func pickerPill(_ title: String, edited: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if edited {
                    Circle().fill(Theme.characteristicNote).frame(width: 8, height: 8)
                        .shadow(color: Theme.characteristicNote, radius: 4)
                        .accessibilityLabel("изменено")
                }
                Typo.notes(title, size: 14, weight: .medium).foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                Icon(.chevronDown, size: 14, color: Theme.textTertiary)
            }
            // Canvas: padding 0 12 0 14 inside a 1 pt border.
            .padding(.leading, 15).padding(.trailing, 13)
            .frame(height: 36)
            .background(Capsule().fill(Theme.cardFill))
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }

    /// «Гриф | Таб» (120 pt).
    private var neckTabSwitch: some View {
        Segments(options: [(false, "Гриф"), (true, "Таб")], selection: Binding(get: { fretboard.tabView }, set: { tab in
            if tab && fretboard.pathKind == nil { fretboard.startPath(from: nil) }
            fretboard.tabView = tab
        }))
        .frame(width: 120)
    }

    /// «● G тоника  ● B D аккорд  ● остальные» (11 pt, dots 12 / 9 / 7, gap 12).
    private var legend: some View {
        let names = fretboard.legendNames
        // The canvas legend starts 2 pt in (inline-flex spans).
        return HStack(spacing: 12) {
            legendItem(dot: 12, color: NeckPortrait.gold, text: "\(names.tonic) тоника")
            if !names.chord.isEmpty {
                legendItem(dot: 9, color: Color(red: 143 / 255, green: 196 / 255, blue: 1, opacity: 0.95), text: "\(names.chord) аккорд")
            }
            legendItem(dot: 7, color: Color(red: 150 / 255, green: 156 / 255, blue: 166 / 255, opacity: 0.7), text: "остальные")
        }
        .padding(.leading, 2)
    }

    private func legendItem(dot: CGFloat, color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: dot, height: dot)
            Typo.notes(text, size: 11).foregroundStyle(Theme.textTertiary).lineLimit(1)
        }
        .frame(height: 13)
    }

    @State private var shownFretRange: ClosedRange<Int> = 1...12
    @State private var dismissedNoPositions = false

    /// Open strings (fixed row, 30 pt) and the scrolling neck (356 pt) — canvas «весь гриф, листается».
    private func wholeNeck(height: CGFloat, sizing: NeckPortrait.NoteSizing) -> some View {
        let courses = app.instrument.courses.count
        let lh = fretboard.settings.leftHanded
        let cells = fretboard.cells()
        return VStack(spacing: 0) {
            openRow(cells: cells.filter { $0.fret == 0 }, courses: courses, leftHanded: lh)
            ScrollingNeck(courses: courses, fretCount: app.instrument.fretCount, window: 1...min(12, app.instrument.fretCount), height: height,
                          openRowOutside: true, leftHanded: lh, capoShift: fretboard.fretsFromCapo ? app.instrument.capo : 0,
                          onVisible: { r in
                              shownFretRange = r
                              fretboard.playFrets = r
                          }, frozen: scrub != nil) { frets in
                neckPortrait(cells: cells, frets: frets, sizing: sizing, openBand: false)
                    .coaching(sizing == .scale ? CoachCatalog.firstTonic(cells) : nil)
            }
        }
        .frame(width: 350, height: height + 30)
        .overlay {
            if fretboard.positions.isEmpty && !dismissedNoPositions { noPositionsCard }
        }
    }

    /// Canvas «Открытые струны»: «0» 11 semibold, circles on #0d0e10 with a 2 pt ring — tonic 24 gold, chord tones 14
    /// blue with the name, the rest 10 grey.
    private func openRow(cells: [NeckCell], courses: Int, leftHanded: Bool) -> some View {
        let boardX: CGFloat = leftHanded ? 18 : 22
        let g = NeckPortrait.Geometry(size: CGSize(width: ScrollingNeck.boardWidth, height: 30), courses: courses, frets: 0...1, leftHanded: leftHanded)
        return ZStack(alignment: .topLeading) {
            Color.clear
            Text("0").font(Typo.inter(11, .semibold)).foregroundStyle(Theme.textSecondary)
                .frame(width: 18, alignment: .trailing)
                .position(x: leftHanded ? 341 : 9, y: 15)
            ForEach(cells) { cell in
                let plain = fretboard.noteSpot != nil
                let tonic = !plain && cell.role == .tonic, chord = !plain && cell.role == .chordTone
                let size: CGFloat = tonic ? 24 : (chord ? 14 : 10)
                let color: Color = tonic ? NeckPortrait.gold : (chord ? Color(hex: 0x8fc4ff) : Color(red: 150 / 255, green: 156 / 255, blue: 166 / 255, opacity: 0.8))
                Typo.notes(tonic || chord ? cell.label : "", size: 10, weight: .bold, fixed: true)
                    .foregroundStyle(tonic || chord ? color : Theme.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .frame(width: size, height: size)
                    .background(Circle().fill(Color(hex: 0x0d0e10)))
                    .overlay(Circle().strokeBorder(color, lineWidth: 2))
                    .opacity(cell.emphasis == .faint ? 0.4 : 1)
                    .position(x: boardX + g.x(course: cell.course), y: 15)
                    .onTapGesture {
                        let spot = NeckSpot(course: cell.course, fret: 0)
                        withAnimation(Motion.out(Motion.Duration.base)) { fretboard.noteSpot = fretboard.noteSpot == spot ? nil : spot }
                        fretboard.tap(course: cell.course, fret: 0)
                    }
            }
        }
        .frame(width: 350, height: 30)
    }

    /// Canvas «Удобных позиций нет» (FretNoPositions).
    private var noPositionsCard: some View {
        VStack(spacing: 0) {
            Text("Удобных позиций нет").font(Typo.inter(16, .semibold)).foregroundStyle(Theme.textPrimary)
            Text("В этом строе гамма не укладывается в 4 лада. Покажем все ноты на грифе.")
                .font(Typo.inter(13)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                .padding(.top, 8)
            Button { dismissedNoPositions = true } label: {
                Text("Показать все ноты").font(Typo.inter(15, .semibold)).foregroundStyle(Theme.background)
                    .padding(.horizontal, 18).frame(height: 44)
                    .background(Capsule().fill(Theme.textPrimary))
            }
            .buttonStyle(PressableStyle())
            .padding(.top, 14)
        }
        .padding(18)
        .frame(width: 310)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(hex: 0x141518, opacity: 0.96)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.hairlineStrong, lineWidth: 1))
    }

    /// «Лады 1–12 из 24» / «листайте вверх-вниз · нажмите ноту» + «Сыграть».
    private var scaleFooter: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Лады \(shownFretRange.lowerBound)–\(shownFretRange.upperBound) из \(app.instrument.fretCount)")
                    .font(Typo.inter(14, .medium)).foregroundStyle(Theme.textPrimary)
                Text("листайте вверх-вниз · нажмите ноту").font(Typo.caption).foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            playButton
        }
        .frame(minHeight: 52)
    }

    // MARK: Chord, search, progression (canvas FretChordTab, FixFretSearch, FlowNote3)

    @ViewBuilder private var progressionTab: some View {
        ProgressionTabBody()
    }

    /// The window the mode's neck scrolls to: «Аккорд» 9 frets from two below the shape, «Поиск» 9 from one below the
    /// marks, «Прогрессия» 11 from the current chord.
    private var modeWindow: ClosedRange<Int> {
        let maxFret = app.instrument.fretCount
        func window(_ lo: Int, _ count: Int) -> ClosedRange<Int> {
            let start = max(1, min(lo, maxFret - count + 1))
            return start...min(maxFret, start + count - 1)
        }
        switch fretboard.mode {
        case .chord:
            let fretted = (fretboard.currentVoicing?.notes ?? []).map(\.fret).filter { $0 > 0 }
            return window((fretted.min() ?? 3) - 2, 9)
        case .search:
            return window((fretboard.marked.map(\.fret).min() ?? 4) - 1, 9)
        case .progression:
            // Canvas FlowNote3: the A barre at 5–7 shows frets 2–12.
            let p = fretboard.progression
            let fretted = (p.voiced[safe: p.current]?.voicing?.notes ?? []).map(\.fret).filter { $0 > 0 }
            return window(fretted.min().map { $0 - 3 } ?? p.visibleFrets.lowerBound, 11)
        case .scale:
            return 1...min(12, maxFret)
        }
    }

    private func modeNeck(sizing: NeckPortrait.NoteSizing) -> some View {
        // Canvas FlowNote3 shows only the sounding chord (no faint next chord).
        let cells = fretboard.cells().filter { sizing != .progression || $0.emphasis != .faint }
        let muted: Set<Int> = fretboard.mode == .chord
            ? Set((fretboard.currentVoicing?.frets.indices ?? 0..<0).filter { fretboard.currentVoicing?.frets[$0] == nil })
            : (fretboard.mode == .progression ? fretboard.progression.mutedCourses : [])
        return ScrollingNeck(courses: app.instrument.courses.count, fretCount: app.instrument.fretCount, window: modeWindow, height: 400,
                             leftHanded: fretboard.settings.leftHanded, capoShift: fretboard.fretsFromCapo ? app.instrument.capo : 0) { frets in
            neckPortrait(cells: cells, frets: frets, sizing: sizing, mutedCourses: muted)
        }
        .frame(width: 350, height: 400)
    }

    /// Root chips (the root and the next two letters) and the quick chord types; 32 pt chips, gap 6.
    private var chordChips: some View {
        let root = fretboard.chordRoot
        let letters = (0..<3).map { NoteName(root.letter.advanced(by: $0)) }
        let roots = [root] + letters.dropFirst()
        return ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(Array(roots.enumerated()), id: \.offset) { i, name in
                    Button { fretboard.chordAnchor = nil; fretboard.chordRoot = name } label: {
                        Chip(text: app.formatter.string(name), style: i == 0 ? .emphasized : .plain)
                    }
                    .buttonStyle(PressableStyle())
                }
                ForEach(["m", "m7", "7", "maj7", "sus4", "dim", "aug", "sus2"], id: \.self) { id in
                    if let chord = ChordLibrary.anyChord(id: id) {
                        Button { fretboard.chordId = id } label: {
                            Chip(text: chordChipName(chord), style: fretboard.chordId == id ? .emphasized : .plain)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                Button { libraryAtScales = false; showLibrary = true } label: { Chip(text: "ещё…") }.buttonStyle(PressableStyle())
            }
            .padding(.horizontal, 1)
        }
        .scrollIndicators(.hidden)
    }

    /// «Am7 · баррэ на 5-м» / «расположение 2 из 4 · A E G C E A» + ‹ › (44).
    private var chordFooter: some View {
        let v = fretboard.currentVoicing
        let title = fretboard.chordName() + (v.map { " · " + ($0.barreFret.map { "баррэ на \($0)-м" } ?? fretboard.voicingTitle($0)) } ?? "")
        let notes = (v?.notes ?? []).sorted { $0.course < $1.course }.map { app.chromaticName($0.pitch).filter { !$0.isNumber } }
        return HStack(spacing: 10) {
            Button { libraryAtScales = false; showLibrary = true } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Typo.notes(title, size: 15, weight: .semibold).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Typo.notes(v == nil ? "расположений нет" : "расположение \(fretboard.voicingIndex + 1) из \(fretboard.voicings.count) · " + notes.joined(separator: " "), size: 12)
                        .foregroundStyle(Theme.textTertiary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            RoundIconButton(icon: .chevronLeft, size: 44, label: "Предыдущее расположение") { fretboard.stepVoicing(-1) }
                .coachAnchor(CoachCatalog.Anchor.voicingPrev)
            RoundIconButton(icon: .chevronRight, size: 44, label: "Следующее расположение") { fretboard.stepVoicing(1) }
                .coachAnchor(CoachCatalog.Anchor.voicingNext)
        }
    }

    private var searchTitle: String {
        let n = fretboard.marked.count
        return n == 0 ? "Отметьте ноты" : "Отмечено \(n) \(ruPlural(n, "нота", "ноты", "нот"))"
    }

    private var progressionTitle: String {
        let p = fretboard.progression
        let key = p.voiced.first.map { app.formatter.string($0.root) } ?? ""
        let numerals = p.progression.chords.map(\.numeral).joined(separator: "–")
        return key.isEmpty ? p.progression.name : "\(key) · \(numerals)"
    }

    /// Four chords, 56 pt, radius 14, gap 6: name 17 semibold, numeral 11 tertiary; the current one lit.
    private var progressionChords: some View {
        let p = fretboard.progression
        let chords = p.progression.chords
        return HStack(spacing: 6) {
            ForEach(Array(p.voiced.enumerated()), id: \.offset) { index, v in
                let selected = index == p.current
                Button { if index == p.current && !p.isPlaying { app.sheet = .progressionChord(index) } else { p.select(index) } } label: {
                    VStack(spacing: 2) {
                        Typo.notes(compactChordName(v.chord.name(root: v.root, formatter: app.formatter)), size: 17, weight: .semibold)
                            .foregroundStyle(Theme.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
                        Typo.notes(chords[safe: index]?.numeral ?? "", size: 11).foregroundStyle(Theme.textTertiary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(RoundedRectangle(cornerRadius: 14).fill(selected ? Theme.textPrimary.opacity(0.12) : Color.white.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? Theme.textPrimary.opacity(0.7) : Theme.hairline, lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    /// «A · баррэ от 5-го лада» / «такт 1 из 4 · следующий E — рядом, 7-й лад» + «Сыграть».
    private var progressionFooter: some View {
        let p = fretboard.progression
        let v = p.voiced[safe: p.current]
        let next = p.voiced.isEmpty ? nil : p.voiced[safe: (p.current + 1) % p.voiced.count]
        func shape(_ voicing: ChordVoicing) -> String {
            if voicing.usesOpenStrings && voicing.lowestFret <= 4 { return "открытый" }
            return (voicing.barreFret != nil ? "баррэ от " : "от ") + "\(voicing.lowestFret)-го лада"
        }
        let title = (v.map { compactChordName($0.chord.name(root: $0.root, formatter: app.formatter)) } ?? "") + (v?.voicing.map { " · " + shape($0) } ?? "")
        var caption = "такт \(p.current + 1) из \(max(1, p.voiced.count))"
        if let next, let nv = next.voicing, let cv = v?.voicing {
            let near = abs(nv.lowestFret - cv.lowestFret) <= 2
            caption += " · следующий \(compactChordName(next.chord.name(root: next.root, formatter: app.formatter))) — \(near ? "рядом" : "сдвиг"), \(nv.lowestFret)-й лад"
        }
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Typo.notes(title, size: 14, weight: .medium).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Typo.notes(caption, size: 12).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { p.toggle() } label: {
                HStack(spacing: 8) {
                    Icon(p.isPlaying ? .stop : .play, size: 18, color: Theme.background)
                    Text(p.isPlaying ? "Стоп" : "Сыграть").font(Typo.inter(16, .semibold)).foregroundStyle(Theme.background)
                }
                .padding(.leading, 14).padding(.trailing, 18).frame(height: 52)
                .background(Capsule().fill(Theme.textPrimary))
                .shadow(color: .black.opacity(0.35), radius: 9, y: 6)
                .fixedSize()
            }
            .buttonStyle(PressableStyle())
            .layoutPriority(1)
        }
    }

    /// The canvas neck for a range of frets (steel board, canvas note sizes).
    func neckPortrait(cells: [NeckCell], frets: ClosedRange<Int>, sizing: NeckPortrait.NoteSizing, openBand: Bool = true,
                      mutedCourses: Set<Int> = []) -> NeckPortrait {
        NeckPortrait(courses: app.instrument.courses.count, frets: frets, cells: cells,
                     leftHanded: fretboard.settings.leftHanded,
                     capo: app.instrument.capo > 0 ? app.instrument.capo : nil,
                     strumming: fretboard.strumming,
                     strumOrder: fretboard.strumOrder,
                     chordMode: fretboard.selectedChord != nil || fretboard.mode == .progression || fretboard.chordPreview != nil,
                     playingMode: fretboard.isPlaying,
                     mutedCourses: mutedCourses,
                     fan: NeckFan(app.instrument.multiscale, courses: app.instrument.courses.count),
                     sizing: sizing, openBand: openBand,
                     onTap: { course, fret in
                         if fretboard.mode == .search { fretboard.toggleMark(course: course, fret: fret) }
                         if fretboard.mode == .scale && fretboard.pathKind == nil && !fretboard.isTraining {
                             // «нажмите ноту» → FlowNote1; the same note again closes it.
                             let spot = NeckSpot(course: course, fret: fret)
                             withAnimation(Motion.out(Motion.Duration.base)) { fretboard.noteSpot = fretboard.noteSpot == spot ? nil : spot }
                         }
                         fretboard.tap(course: course, fret: fret)
                     },
                     onLongPress: { course, fret, point in
                         fretboard.menuSpot = NeckSpot(course: course, fret: fret)
                         withAnimation(Motion.out(Motion.Duration.quick)) { menuPoint = point }
                     },
                     onScrub: { value in
                         if let value {
                             if scrub?.spot != value.0 { fretboard.tap(course: value.0.course, fret: value.0.fret) }
                             scrub = (value.0, value.1)
                         } else if let last = scrub {
                             // «отпустите — нота поставлена»: the held note opens FlowNote1.
                             scrub = nil
                             withAnimation(Motion.out(Motion.Duration.base)) { fretboard.noteSpot = last.spot }
                         }
                     },
                     scrubs: fretboard.mode == .scale && fretboard.pathKind == nil && !fretboard.isTraining && fretboard.noteSpot == nil)
    }

    /// «E · Фригийский доминант ▾» (44 pt capsule), reset when edited, «Вид и подписи».
    private var scaleRow: some View {
        HStack(spacing: 8) {
            if fretboard.pathKind != nil {
                // Visible way out of the path (it was only inside the path sheet).
                RoundIconButton(icon: .close, size: 44, label: "Выйти из пути") {
                    if fretboard.isPlaying { fretboard.stopPlayback() }
                    fretboard.pathKind = nil
                }
            }
            Button { app.sheet = .fretScale } label: {
                HStack(spacing: 6) {
                    if fretboard.isEdited {
                        Circle().fill(Theme.characteristicNote).frame(width: 8, height: 8)
                            .shadow(color: Theme.characteristicNote, radius: 4)
                            .accessibilityLabel("изменено")
                    }
                    Typo.notes(scaleTitle, size: 14, weight: .medium).kerning(-0.14).foregroundStyle(Theme.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity, alignment: .leading)
                    Icon(.chevronDown, size: 14, color: Theme.textTertiary)
                }
                .padding(.leading, 14).padding(.trailing, 10)
                .frame(height: 44)
                .background(Capsule().fill(Theme.cardFill))
                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Гамма: \(scaleTitle)")
            if fretboard.isEdited {
                Button { fretboard.resetEdits() } label: {
                    Icon(.refresh, size: 18, color: Theme.characteristicNote)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Theme.knobFill))
                        .overlay(Circle().strokeBorder(Theme.hairlineStrong, lineWidth: 1))
                        .shadow(color: .black.opacity(0.6), radius: 9, y: 8)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Сбросить изменения")
            }
            if fretboard.pathKind == nil {
                // Visible way into «Путь» (it was only in the note's long-press menu — user: «не вижу пути»).
                Button {
                    fretboard.startPath(from: nil)
                    app.sheet = .fretPath
                } label: {
                    Text("Путь").font(Typo.inter(14, .medium)).foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 14).frame(height: 44)
                        .background(Capsule().fill(Theme.cardFill))
                        .overlay(Capsule().strokeBorder(Theme.hairlineStrong, lineWidth: 1))
                        .fixedSize()
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Путь по грифу")
            }
            RoundIconButton(icon: .rename, size: 44, label: fretboard.pathKind != nil ? "Путь по грифу" : "Вид и подписи") {
                app.sheet = fretboard.pathKind != nil ? .fretPath : .fretView
            }
        }
    }

    private var scaleTitle: String {
        let capo = app.instrument.capo
        return fretboard.scaleTitle + (capo > 0 ? " · капо \(capo)" : "") + (fretboard.pathKind != nil ? " · путь" : "")
    }

    /// FB-14 while training: the result strip, tempo ± and «Стоп».
    private var trainingBar: some View {
        VStack(spacing: 10) {
            PlayCheckPanel(height: 56)
            HStack(spacing: 8) {
                RoundIconButton(icon: .minus, size: 44, label: "Медленнее") { app.metronome.step(-1) }
                VStack(spacing: 0) {
                    Text("\(Int(app.metronome.displayBPM))").font(Typo.inter(22, .semibold)).foregroundStyle(Theme.textPrimary).monospacedDigit()
                    Text(app.playCheck.settings.adaptive ? "BPM · темп по результату" : "BPM").font(Typo.caption).foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity)
                RoundIconButton(icon: .plus, size: 44, label: "Быстрее") { app.metronome.step(1) }
                Button { fretboard.stopTraining() } label: {
                    HStack(spacing: 8) {
                        Icon(.stop, size: 16, color: Theme.background)
                        Text("Стоп").font(Typo.inter(16, .semibold)).foregroundStyle(Theme.background)
                    }
                    .padding(.horizontal, 18).frame(height: 52)
                    .background(Capsule().fill(Theme.textPrimary))
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    /// «Своё окно · лады 5–8 · тяните за ручки» + «Готово» (canvas «правка своего окна ладов»).
    private var windowBar: some View {
        HStack(spacing: 10) {
            let r = fretboard.visibleFrets
            Text("Своё окно · лады \(r.lowerBound)–\(r.upperBound) · тяните за ручки")
                .font(Typo.inter(13, .medium)).foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Готово") { withAnimation(Motion.out(Motion.Duration.base)) { editingWindow = false } }
                .font(Typo.inter(13, .semibold)).foregroundStyle(Theme.background)
                .padding(.horizontal, 14).frame(height: 32)
                .background(Capsule().fill(Theme.textPrimary))
                .buttonStyle(PressableStyle())
        }
        .padding(.leading, 14).padding(.trailing, 6)
        .frame(height: 44)
        .background(Capsule().fill(Theme.cardFill))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
    }

    /// Note menu under the pressed note (canvas «меню ноты»), kept on screen.
    @ViewBuilder private var noteMenu: some View {
        if let point = menuPoint, let spot = fretboard.menuSpot {
            GeometryReader { proxy in
                // Canvas «меню ноты»: the screen dims and blurs, the pressed note grows to 52 pt with a halo.
                let menuHeight: CGFloat = 256
                let below = point.y + 38
                let y = below + menuHeight <= proxy.size.height ? below : max(8, point.y - 38 - menuHeight)
                ZStack(alignment: .topLeading) {
                    Color(hex: 0x030304, opacity: 0.55)
                        .ignoresSafeArea()
                        .onTapGesture { closeMenu() }
                    if !phoneLandscape {
                        Typo.notes(fretboard.noteName(spot), size: 17, weight: .bold, fixed: true)
                            .foregroundStyle(Color(hex: 0x0c0d0f))
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .frame(width: 52, height: 52)
                            .background(Circle().fill(Color(red: 245 / 255, green: 239 / 255, blue: 227 / 255, opacity: 0.98)))
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                            .background(Circle().stroke(Color(red: 246 / 255, green: 243 / 255, blue: 236 / 255, opacity: 0.18), lineWidth: 6).frame(width: 58, height: 58))
                            .shadow(color: .black.opacity(0.7), radius: 15, y: 14)
                            .position(point)
                            .allowsHitTesting(false)
                    }
                    NoteMenu(spot: spot, close: closeMenu)
                        .offset(x: min(max(16, point.x - 116), proxy.size.width - 248), y: phoneLandscape ? 40 : y)
                }
            }
            .transition(.opacity)
        }
    }

    private func closeMenu() {
        withAnimation(Motion.out(Motion.Duration.quick)) { menuPoint = nil }
        if app.sheet == nil { fretboard.menuSpot = nil }
    }

    // MARK: Neck

    private var shownFrets: ClosedRange<Int> {
        // Editing the window: the frets around it stay in view, dimmed (canvas «правка своего окна»).
        if editingWindow, let windowContext { return windowContext }
        let r = fretboard.visibleFrets
        guard zoom > 1.01, fretboard.settings.neckView != .wholeNeck else { return r }
        let count = max(2, Int((Double(r.count) / Double(zoom)).rounded()))
        let start = r.lowerBound + (r.count - count) / 2
        return start...(start + count - 1)
    }

    @ViewBuilder private var neck: some View {
        let cells = fretboard.cells()
        let s = fretboard.settings
        Group {
            if fretboard.mode == .scale && fretboard.pathKind != nil {
                pathNeck(cells: cells)
            } else if s.neckView == .wholeNeck && !fretboard.hasPreview && (fretboard.mode == .scale || fretboard.mode == .search) {
                // The whole neck on one screen (user: «нужен режим, где я вижу весь гриф, а не кусок»).
                neckView(cells: cells, frets: fretboard.visibleFrets, overview: true)
            } else {
                neckView(cells: cells, frets: shownFrets)
            }
        }
        .overlay {
            if fretboard.positions.isEmpty && s.neckView != .window {
                VStack(spacing: 6) {
                    Text("Для этой гаммы позиции не строятся").font(Typo.inter(15, .medium)).foregroundStyle(Theme.textPrimary)
                    Text("Показан весь гриф").font(Typo.inter(13)).foregroundStyle(Theme.textTertiary)
                }
                .multilineTextAlignment(.center)
                .padding(18)
                .frame(maxWidth: 300)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(hex: 0x141518, opacity: 0.92)))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairlineStrong, lineWidth: 1))
                .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            if showZoom {
                HStack(spacing: 6) {
                    Icon(.search, size: 12, color: Theme.textTertiary)
                    Text("×" + String(format: "%.1f", zoom).replacingOccurrences(of: ".", with: ","))
                        .font(Typo.chip).foregroundStyle(Theme.textPrimary)
                }
                .padding(.horizontal, 12).frame(height: 30)
                .background(Capsule().fill(Color(hex: 0x141518, opacity: 0.95)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                .padding(.bottom, 82)
                .transition(.opacity)
            }
        }
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    zoom = (pinchBase * value.magnification).clamped(to: 1...2.5)
                    showZoom = true
                    zoomTask?.cancel()
                }
                .onEnded { _ in
                    pinchBase = zoom
                    zoomTask = Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        guard !Task.isCancelled else { return }
                        withAnimation(Motion.out(Motion.Duration.base)) { showZoom = false }
                    }
                }
        )
        .animation(Motion.out(Motion.Duration.base), value: showZoom)
    }

    /// The whole neck with the whole path on one screen (FB-20): no scrolling, nothing to follow — the path was
    /// running off the screen on the iPhone in both orientations.
    private func pathNeck(cells: [NeckCell]) -> some View {
        neckView(cells: cells, frets: 0...app.instrument.fretCount, path: fretboard.pathNotes, pathCurrent: fretboard.pathIndex,
                 overview: true)
    }

    /// «14 / 20 · автопрокрутка … · ❙❙» and «↓ К текущей ноте» (canvas «путь, портрет»).
    private var pathBar: some View {
        VStack(spacing: 10) {
            if !autoScroll {
                Button { autoScroll = true } label: {
                    HStack(spacing: 6) {
                        Text("↓").font(Typo.inter(13, .semibold))
                        Text("К текущей ноте").font(Typo.inter(14, .medium))
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 16).frame(height: 40)
                    .background(Capsule().fill(Theme.cardFill))
                    .background(Capsule().fill(Theme.background.opacity(0.85)))
                    .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
            }
            HStack(spacing: 10) {
                Chip(text: "\((fretboard.pathIndex ?? 0) + 1) / \(fretboard.pathNotes.count)")
                Text(autoScroll ? (fretboard.pathIndex == nil ? fretboard.pathSummary + " · ▶ — сыграть" : pathKindTitle) : "Автопрокрутка на паузе — вы листали гриф")
                    .font(Typo.caption).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                RoundIconButton(icon: .sliders, size: 44, label: "Путь по грифу") { app.sheet = .fretPath }
                PrimaryRoundButton(icon: fretboard.isPlaying ? .pause : .play, size: 44, iconSize: 18,
                                   label: fretboard.isPlaying ? "Пауза" : "Сыграть путь") {
                    autoScroll = true
                    fretboard.togglePlayback()
                }
            }
        }
    }

    private var pathKindTitle: String {
        switch fretboard.pathKind {
        case .threePerString?: return "Путь: 3 ноты на струну"
        case .fourDiagonal?: return "Путь: 4 ноты наискосок"
        case .oneString?:
            // «По одной струне · 5-я»: strings count from the highest (canvas «путь по одной струне»).
            guard let course = fretboard.pathNotes.first?.course else { return "Путь: по одной струне" }
            return "Путь: по одной струне · \(app.instrument.courses.count - course)-я"
        case nil: return ""
        }
    }

    /// - Parameter rotation: ±90 for the landscape board (the neck is drawn upright, then turned).
    private func neckView(cells: [NeckCell], frets: ClosedRange<Int>, path: [FretNote] = [], pathCurrent: Int? = nil,
                          rotation: Double = 0, overview: Bool = false) -> some View {
        let s = fretboard.settings
        // Portrait: the left-handed mirror. Landscape: course 0 (lowest) lands at the bottom after −90° and at the top
        // after +90° (left-handed, nut on the right) — flipped to honour «низкая струна сверху».
        let flip = rotation == 0 ? s.leftHanded : (s.leftHanded != s.lowStringOnTop)
        return NeckPortrait(courses: app.instrument.courses.count, frets: frets, cells: cells,
                     leftHanded: flip,
                     capo: app.instrument.capo > 0 ? app.instrument.capo : nil,
                     strumming: fretboard.strumming,
                     strumOrder: fretboard.strumOrder,
                     chordMode: fretboard.selectedChord != nil || fretboard.mode == .progression || fretboard.chordPreview != nil,
                     path: path, pathLabels: path.map { fretboard.pathLabel($0) }, pathCurrent: pathCurrent,
                     playingMode: fretboard.isPlaying,
                     mutedCourses: fretboard.chordPreview.map { v in Set(v.frets.indices.filter { v.frets[$0] == nil }) } ?? (fretboard.mode == .chord ? Set((fretboard.currentVoicing?.frets.indices ?? 0..<0).filter { fretboard.currentVoicing?.frets[$0] == nil })
                        : (fretboard.mode == .progression ? fretboard.progression.mutedCourses : [])),
                     labelRotation: -rotation,
                     fan: NeckFan(app.instrument.multiscale, courses: app.instrument.courses.count),
                     overview: overview,
                     onTap: { course, fret in
                         if fretboard.mode == .search { fretboard.toggleMark(course: course, fret: fret) }
                         fretboard.tap(course: course, fret: fret)
                     },
                     onLongPress: { course, fret, point in
                         fretboard.menuSpot = NeckSpot(course: course, fret: fret)
                         // A turned neck reports unturned points: the landscape menu opens mid-board instead.
                         let shown = rotation == 0 ? point : CGPoint(x: LandscapeCanvas<EmptyView>.size.width / 2, y: 84)
                         withAnimation(Motion.out(Motion.Duration.quick)) { menuPoint = shown }
                     })
            .overlay { if editingWindow { windowFrame(frets) } }
            .accessibilityElement()
            .accessibilityLabel("Гриф, \(scaleTitle)")
            .accessibilityValue(positionLabel.replacingOccurrences(of: "\n", with: ", "))
    }

    /// Window frame with two drag handles (top and bottom) moving the window by frets.
    private func windowFrame(_ frets: ClosedRange<Int>) -> some View {
        GeometryReader { proxy in
            let g = NeckPortrait.Geometry(size: proxy.size, courses: app.instrument.courses.count, frets: frets, leftHanded: false,
                                          fan: NeckFan(app.instrument.multiscale, courses: app.instrument.courses.count))
            let start = fretboard.settings.windowStart
            let end = start + fretboard.settings.windowLength - 1
            let top = start <= frets.lowerBound ? 0 : g.wire(start - 1)
            let bottom = min(proxy.size.height, g.wire(min(end, frets.upperBound)) + 4)
            let row = max(12, (bottom - top) / CGFloat(max(1, fretboard.settings.windowLength)))
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Theme.textPrimary, lineWidth: 2)
                .overlay(alignment: .top) { handle.offset(y: -22).gesture(handleDrag(top: true, row: row)) }
                .overlay(alignment: .bottom) { handle.offset(y: 22).gesture(handleDrag(top: false, row: row)) }
                .padding(.horizontal, -6)
                .frame(height: max(24, bottom - top))
                .offset(y: top)
        }
    }

    private func context(for start: Int, length: Int) -> ClosedRange<Int> {
        let maxFret = app.instrument.fretCount
        return max(0, start - 3)...min(maxFret, start + length - 1 + 3)
    }

    private var handle: some View {
        Capsule().fill(Theme.textPrimary).frame(width: 48, height: 18)
            .overlay(Capsule().fill(Theme.background).frame(width: 22, height: 3))
            .shadow(color: .black.opacity(0.5), radius: 4, y: 3)
            .frame(width: 88, height: 44)
            .contentShape(Rectangle())
    }

    private func handleDrag(top: Bool, row: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4).onEnded { value in
            let steps = Int((value.translation.height / row).rounded())
            guard steps != 0 else { return }
            var s = fretboard.settings
            let maxFret = app.instrument.fretCount
            if top {
                let start = (s.windowStart + steps).clamped(to: 0...(s.windowStart + s.windowLength - 2))
                s.windowLength += s.windowStart - start
                s.windowStart = start
            } else {
                s.windowLength = (s.windowLength + steps).clamped(to: 2...(maxFret - s.windowStart + 1))
            }
            fretboard.settings = s
            // The frets around follow only when the window reaches the edge of what is shown.
            if let c = windowContext, s.windowStart <= c.lowerBound || s.windowStart + s.windowLength - 1 >= c.upperBound {
                windowContext = context(for: s.windowStart, length: s.windowLength)
            }
        }
    }

    // MARK: Chords (7 columns, gap 5, 52 pt)

    private var chordStrip: some View {
        HStack(spacing: 5) {
            ForEach(Array(fretboard.keyChords.enumerated()), id: \.offset) { index, chord in
                let selected = fretboard.selectedChord == index
                Button { fretboard.tapChord(index) } label: {
                    VStack(spacing: 1) {
                        // Canvas «Обозначения — гриф»: chord symbols stay in letters in solfège («соль♯°» does not fit).
                        Typo.notes(compactChordName(chord.name(formatter: app.chordFormatter)), size: 15, weight: .semibold)
                            .foregroundStyle(selected ? Theme.textPrimary : Theme.textMuted)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Typo.notes(chord.romanNumeral, size: 10).foregroundStyle(Theme.textTertiary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? Theme.textPrimary.opacity(0.12) : Color.white.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? Theme.textPrimary.opacity(0.7) : Theme.hairline, lineWidth: 1))
                    .overlay {
                        if selected && !fretboard.strumming.isEmpty {
                            RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.textPrimary.opacity(0.9), lineWidth: 2).padding(-4)
                                .transition(.opacity)
                        }
                    }
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("\(chord.name(formatter: app.formatter)), \(chord.romanNumeral)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .animation(Motion.out(Motion.Duration.base), value: fretboard.strumming)
        .disabled(editingWindow).opacity(editingWindow ? 0.4 : 1)
    }

    // MARK: Navigation

    /// «лады 3–8», with a capo counted from it (PRD 6.2.5): «от капо 0–5».
    private func fretsText(_ r: ClosedRange<Int>) -> String {
        let capo = app.instrument.capo
        guard capo > 0 else { return "лады \(r.lowerBound)–\(r.upperBound)" }
        return "от капо \(max(0, r.lowerBound - capo))–\(max(0, r.upperBound - capo))"
    }

    private var positionLabel: String {
        let r = fretboard.visibleFrets
        let shown = app.instrument.capo > 0 ? (fretboard.currentPosition?.fretRange ?? shownFrets) : shownFrets
        switch fretboard.settings.neckView {
        case .position:
            if fretboard.positions.isEmpty { return "Позиция —\n" + fretsText(r) }
            if fretboard.positionAnchor != nil { return "От ноты\n" + fretsText(shown) }
            // The last positions are cut by fret 24 (user: positions end at the last fret) — say so.
            let edge = fretboard.currentPosition?.isTruncated == true ? " · край грифа" : ""
            return "Позиция \(fretboard.settings.positionNumber)/\(fretboard.positions.count)\n" + fretsText(shown) + edge
        case .window: return "Своё окно\n" + fretsText(r)
        case .wholeNeck: return "Весь гриф\n" + fretsText(r)
        }
    }

    private var navigation: some View {
        HStack(spacing: 8) {
            RoundIconButton(icon: .chevronLeft, size: 44, label: "Предыдущая позиция") { fretboard.stepPosition(-1) }
            // One visible choice of the view instead of a hidden tap / long press on the label.
            Menu {
                Button("Позиции") { fretboard.selectPosition(max(1, fretboard.settings.positionNumber)) }
                Button("Весь гриф") { fretboard.selectPosition(nil) }
                Button("Своё окно ладов…") { startEditingWindow() }
                Button("Путь по грифу") {
                    fretboard.startPath(from: nil)
                    app.sheet = .fretPath
                }
                Button("Тренировать с проверкой") { fretboard.startTraining() }
            } label: {
                positionText.frame(maxWidth: .infinity).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Вид грифа: " + positionLabel.replacingOccurrences(of: "\n", with: ", "))
            RoundIconButton(icon: .chevronRight, size: 44, label: "Следующая позиция") { fretboard.stepPosition(1) }
            // Visible entry to the playback settings (user: a long press on «Сыграть» was not discoverable).
            // While the drone sounds the button is lit and turns it off in one tap (FB-13).
            if fretboard.isDroning {
                PrimaryRoundButton(icon: .waveform, size: 44, iconSize: 18, label: "Выключить бурдон") { fretboard.stopDrone() }
            } else {
                RoundIconButton(icon: .sliders, size: 44, label: "Настройки проигрывания") { app.sheet = .fretPlay }
            }
            playButton
        }
        .disabled(editingWindow).opacity(editingWindow ? 0.4 : 1)
    }

    private func startEditingWindow() {
        var s = fretboard.settings
        let r = fretboard.visibleFrets
        s.neckView = .window
        s.windowStart = max(1, r.lowerBound)
        s.windowLength = max(2, min(r.count, 6))
        fretboard.settings = s
        windowContext = context(for: s.windowStart, length: s.windowLength)
        withAnimation(Motion.out(Motion.Duration.base)) { editingWindow = true }
    }

    private var positionText: some View {
        let lines = positionLabel.split(separator: "\n").map(String.init)
        let first = lines.first ?? ""
        let parts = first.split(separator: " ", maxSplits: 1).map(String.init)
        return VStack(spacing: 0) {
            (Text(parts.first ?? "") + Text(parts.count > 1 ? " " : "") + Text(parts.count > 1 ? parts[1] : "").foregroundColor(Theme.textPrimary).font(Typo.inter(12, .semibold)))
            Text(lines.count > 1 ? lines[1] : "")
        }
        .font(Typo.inter(12)).foregroundStyle(Theme.textTertiary)
        .lineSpacing(2)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .multilineTextAlignment(.center)
    }

    /// «▶ Сыграть» / «❙❙ Пауза»: ivory pill 52 pt, 16 semibold; long press — the playback sheet.
    private var playButton: some View {
        Button { fretboard.togglePlayback() } label: {
            HStack(spacing: 8) {
                Icon(fretboard.isPlaying ? .pause : .play, size: 18, color: Theme.background)
                Text(fretboard.isPlaying ? "Пауза" : (fretboard.canResume ? "Дальше" : "Сыграть")).font(Typo.inter(16, .semibold)).foregroundStyle(Theme.background)
            }
            .padding(.leading, 14).padding(.trailing, 18)
            .frame(height: 52)
            .background(Capsule().fill(Theme.textPrimary))
            .shadow(color: .black.opacity(0.35), radius: 9, y: 6)
            .fixedSize()
        }
        .buttonStyle(PressableStyle())
        .layoutPriority(1)
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in app.sheet = .fretPlay })
        .accessibilityLabel(fretboard.isPlaying ? "Пауза" : "Сыграть гамму")
        .accessibilityHint("Долгое нажатие — порядок и темп")
    }

    // MARK: Landscape (canvas «Гриф — альбом», «низкая струна сверху», «путь — альбом»; 844 × 390)

    /// macOS wide window (until the Mac boards): the horizontal neck.
    private var landscape: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                scaleRow
                RoundIconButton(icon: .gear, label: "Настройки") { app.showSettings = true }
            }
            .padding(.horizontal, 20)
            NeckView(horizontal: true, availableAcross: 220, zoom: $zoom, scrollTarget: fretboard.visibleFrets.lowerBound)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 12)
            HStack(spacing: 8) { chordStrip; playButton }.padding(.horizontal, 20)
        }
        .padding(.vertical, 8)
    }

    /// Header (top 16, from x 50, 760 wide): «Вид» 44, title 15 medium, view chip, «Сыграть» 48.
    /// Neck 780 × 300 at (50, 82): the portrait neck turned −90° (nut on the left), +90° for the left-handed.
    /// Canvas FixLandScale: the scale on the whole neck, turned −90° and scrolled along x.
    private var canvasLandscape: Bool {
        fretboard.mode == .scale && fretboard.pathKind == nil && !fretboard.isTraining && !fretboard.settings.leftHanded
    }

    private var landscapeBoard: some View {
        LandscapeCanvas {
            ZStack(alignment: .topLeading) {
                if canvasLandscape {
                    canvasLandscapeHeader.board(x: 32, y: 16, width: 780)
                    LandscapeWholeNeck(fretCount: app.instrument.fretCount, courses: app.instrument.courses.count,
                                       openCells: fretboard.cells().filter { $0.fret == 0 },
                                       capoShift: fretboard.fretsFromCapo ? app.instrument.capo : 0) { frets in
                        NeckPortrait(courses: app.instrument.courses.count, frets: frets, cells: fretboard.cells(),
                                     capo: app.instrument.capo > 0 ? app.instrument.capo : nil,
                                     playingMode: fretboard.isPlaying,
                                     labelRotation: 90,
                                     sizing: .scale, openBand: false,
                                     onTap: { course, fret in fretboard.tap(course: course, fret: fret) },
                                     onLongPress: { course, fret, _ in
                                         fretboard.menuSpot = NeckSpot(course: course, fret: fret)
                                         withAnimation(Motion.out(Motion.Duration.quick)) { menuPoint = CGPoint(x: 422, y: 84) }
                                     })
                    }
                } else {
                    landscapeHeader.board(x: 50, y: 16, width: 760)
                    landscapeNeck.frame(width: 780, height: 300).clipped().offset(x: 50, y: 82)
                }
            }
            .frame(width: 844, height: 390, alignment: .topLeading)
            .coordinateSpace(name: "fretScreen")
            .overlay(alignment: .topLeading) { noteMenu }
            .overlay(alignment: .top) {
                if let toast = fretboard.toast {
                    DesignToast(icon: .refresh, text: toast).padding(.top, 20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(Motion.out(Motion.Duration.base), value: fretboard.toast)
        }
    }

    /// Canvas FixLandScale header (32, 16, 780 wide): «Вид» 44, «G · Мажор» 15 medium, «Гриф | Таб», legend, ▶ 48.
    private var canvasLandscapeHeader: some View {
        HStack(spacing: 10) {
            RoundIconButton(icon: .rename, size: 44, label: "Вид и подписи") { app.sheet = .fretView }
            Button { app.sheet = .fretScale } label: {
                Typo.notes(scalePillTitle, size: 15, weight: .medium).foregroundStyle(Theme.textPrimary).lineLimit(1)
            }
            .buttonStyle(.plain)
            neckTabSwitch
            Spacer(minLength: 0)
            legend
            PrimaryRoundButton(icon: fretboard.isPlaying ? .pause : .play, size: 48, iconSize: 20,
                               label: fretboard.isPlaying ? "Пауза" : "Сыграть") { fretboard.togglePlayback() }
        }
        .frame(height: 48)
    }

    private var landscapeTitle: String {
        switch fretboard.mode {
        case .scale: return scaleTitle
        case .chord:
            let name = fretboard.chordName()
            return fretboard.currentVoicing.map { name + " · " + fretboard.voicingTitle($0) } ?? name
        case .search:
            if fretboard.markedPitches.count < 3 { return "Поиск · отметьте ноты" }
            return fretboard.searchChords.first.map { compactChordName($0.name(formatter: app.formatter)) } ?? "Ничего не найдено"
        case .progression:
            let p = fretboard.progression
            return p.voiced[safe: p.current].map { compactChordName($0.chord.name(root: $0.root, formatter: app.formatter)) + " · " + p.progression.name } ?? p.progression.name
        }
    }

    @ViewBuilder private var landscapeHeader: some View {
        HStack(spacing: 10) {
            if fretboard.pathKind != nil && fretboard.mode == .scale {
                RoundIconButton(icon: .chevronLeft, size: 44, label: "Назад") {
                    if fretboard.isPlaying { fretboard.togglePlayback() }
                    fretboard.pathKind = nil
                }
                Typo.notes(scaleTitle, size: 15, weight: .medium).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Button { app.sheet = .fretPath } label: {
                    HeaderChip(text: pathKindTitle.replacingOccurrences(of: "Путь: ", with: "").capitalizedFirst, icon: .chevronDown)
                }
                .buttonStyle(PressableStyle())
                Spacer(minLength: 8)
                Chip(text: "\((fretboard.pathIndex ?? -1) + 1) / \(fretboard.pathNotes.count)", style: .muted)
                    .accessibilityLabel("Нота \((fretboard.pathIndex ?? -1) + 1) из \(fretboard.pathNotes.count)")
            } else {
                RoundIconButton(icon: .sliders, size: 44, label: "Вид и подписи") { app.sheet = .fretView }
                Button { app.sheet = .fretScale } label: {
                    Typo.notes(landscapeTitle, size: 15, weight: .medium).foregroundStyle(Theme.textPrimary).lineLimit(1)
                }
                .buttonStyle(.plain)
                .disabled(fretboard.mode != .scale)
                .accessibilityLabel("Гамма: \(landscapeTitle)")
                Spacer(minLength: 8)
                if fretboard.mode == .scale { viewMenu }
                if fretboard.mode == .chord {
                    RoundIconButton(icon: .chevronLeft, size: 44, label: "Предыдущее расположение") {
                        if fretboard.voicingIndex > 0 { fretboard.voicingIndex -= 1; fretboard.playVoicing() }
                    }
                    RoundIconButton(icon: .chevronRight, size: 44, label: "Следующее расположение") {
                        if fretboard.voicingIndex + 1 < fretboard.voicings.count { fretboard.voicingIndex += 1; fretboard.playVoicing() }
                    }
                }
                if fretboard.mode == .progression {
                    let p = fretboard.progression
                    RoundIconButton(icon: .chevronLeft, size: 44, label: "Предыдущий аккорд") { p.select(max(0, p.current - 1)) }
                    RoundIconButton(icon: .chevronRight, size: 44, label: "Следующий аккорд") { p.select(min(p.voiced.count - 1, p.current + 1)) }
                }
            }
            if fretboard.isDroning {
                RoundIconButton(icon: .waveform, size: 44, label: "Выключить бурдон") { fretboard.stopDrone() }
                    .overlay(Circle().strokeBorder(Theme.textPrimary, lineWidth: 1.5))
            }
            let playing = fretboard.mode == .progression ? fretboard.progression.isPlaying : fretboard.isPlaying
            PrimaryRoundButton(icon: playing ? (fretboard.mode == .progression ? .stop : .pause) : .play, size: 48, iconSize: 20,
                               label: playing ? "Пауза" : "Сыграть") {
                switch fretboard.mode {
                case .chord: fretboard.playVoicing(arpeggio: false)
                case .progression: fretboard.progression.toggle()
                default: autoScroll = true; fretboard.togglePlayback()
                }
            }
        }
        .frame(height: 48)
    }

    /// «Весь гриф» / «Позиция 2/7» chip: a menu of the views (FB-6) instead of the portrait arrows.
    private var viewMenu: some View {
        Menu {
            Button("Весь гриф") { fretboard.selectPosition(nil) }
            ForEach(Array(fretboard.positions.indices), id: \.self) { i in
                Button("Позиция \(i + 1) · лады \(fretboard.positions[i].fretRange.lowerBound)–\(fretboard.positions[i].fretRange.upperBound)") {
                    fretboard.selectPosition(i + 1)
                }
            }
        } label: {
            HeaderChip(text: String(positionLabel.split(separator: "\n").first ?? ""))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("Вид: \(positionLabel.replacingOccurrences(of: "\n", with: ", "))")
    }

    /// The whole neck (or the path) scrolls along x; a position, window or chord fits the 780 pt.
    private var landscapeNeck: some View {
        let cells = fretboard.cells()
        let s = fretboard.settings
        let isPath = fretboard.mode == .scale && fretboard.pathKind != nil
        let whole = isPath || (s.neckView == .wholeNeck && !fretboard.hasPreview && (fretboard.mode == .scale || fretboard.mode == .search))
        // A position keeps its place on the neck: 12–13 frets around it instead of 5 stretched over the screen.
        let frets: ClosedRange<Int> = {
            if whole { return 0...app.instrument.fretCount }
            let r = fretboard.visibleFrets
            guard fretboard.mode == .scale, !fretboard.hasPreview else { return r }
            let top = app.instrument.fretCount
            let hi = min(top, max(r.upperBound + 3, max(0, r.lowerBound - 3) + 12))
            return max(0, min(r.lowerBound - 3, hi - 12))...hi
        }()
        let length: CGFloat = 780   // the whole neck fits the board (it was 62 pt a fret and ran off the screen)
        let rotation: Double = s.leftHanded ? 90 : -90
        let courses = app.instrument.courses.count
        // Along-neck position of a fret's cell in the turned board.
        let along: (Int) -> CGFloat = { fret in
            let y = NeckPortrait.cellY(fret: fret, frets: frets, courses: courses, size: CGSize(width: 300, height: length), overview: whole)
            return s.leftHanded ? length - y : y
        }
        return ScrollViewReader { reader in
            ScrollView(.horizontal) {
                neckView(cells: cells, frets: frets, path: isPath ? fretboard.pathNotes : [], pathCurrent: isPath ? fretboard.pathIndex : nil,
                         rotation: rotation, overview: whole)
                    .frame(width: 300, height: length)
                    .rotationEffect(.degrees(rotation))
                    .frame(width: length, height: 300)
                    .overlay(alignment: .topLeading) {
                        ZStack(alignment: .topLeading) {
                            ForEach(Array(frets), id: \.self) { fret in
                                Color.clear.frame(width: 1, height: 1).padding(.leading, along(fret)).id("lfret-\(fret)")
                            }
                        }
                        .allowsHitTesting(false)
                    }
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(!whole)
            .defaultScrollAnchor(s.leftHanded ? .trailing : .leading)
            .simultaneousGesture(DragGesture(minimumDistance: 6).onChanged { _ in if isPath && fretboard.isPlaying { autoScroll = false } })
            .onChange(of: fretboard.pathIndex) { _, index in
                guard isPath, autoScroll, let index, let note = fretboard.pathNotes[safe: index] else { return }
                withAnimation(Motion.out(Motion.Duration.move)) { reader.scrollTo("lfret-\(note.fret)", anchor: .center) }
            }
            .onChange(of: fretboard.pathNotes.first?.fret) { _, fret in
                if isPath, let fret { withAnimation(Motion.out(Motion.Duration.move)) { reader.scrollTo("lfret-\(fret)", anchor: .center) } }
            }
            .onAppear {
                if isPath, let first = fretboard.pathNotes.first { reader.scrollTo("lfret-\(first.fret)", anchor: .center) }
            }
        }
    }
}
