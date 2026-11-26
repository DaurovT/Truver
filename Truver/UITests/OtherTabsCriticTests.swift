import XCTest

/// Exploratory critic pass over the metronome, tuner, tunings, settings and practice tabs (real taps).
final class OtherTabsCriticTests: TruverUITestCase {
    // MARK: helpers

    func containing(_ text: String, _ type: XCUIElement.ElementType = .any) -> XCUIElement {
        app.descendants(matching: type).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    func tapContains(_ text: String, _ type: XCUIElement.ElementType = .any) -> Bool {
        let e = containing(text, type)
        if e.waitForExistence(timeout: 3) { safeTap(e); usleep(700_000); return true }
        XCTFail("Not found containing: \(text)"); return false
    }

    func log(_ s: String) {
        let a = XCTAttachment(string: s); a.name = "log-\(step)"; a.lifetime = .keepAlways; add(a)
        print("CRITIC", s)
    }

    var knobValue: String { (element("Темп").value as? String) ?? "?" }

    func openMetronome() { tab("Метроном"); sleep(1) }

    func openRhythmSheet() { _ = tapContains("Ритм:"); sleep(1) }

    /// Scroll the sheet by dragging within its content.
    func scrollSheet(_ dy: CGFloat) {
        let s = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        s.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75 - dy)))
        usleep(900_000)
    }

    func pickFigure(_ name: String) {
        // Scroll until the figure is visible, then tap it.
        for _ in 0..<12 {
            let e = element(name, .button)
            if e.exists && e.isHittable && e.frame.maxY < app.frame.height - 30 { safeTap(e); usleep(800_000); return }
            scrollSheet(0.35)
        }
        XCTFail("Figure not reached: \(name)")
    }

    // MARK: metronome — note value sheet

    func testA_RhythmSheet() {
        launch()
        openMetronome()
        shot("metro-main", tree: true)
        openRhythmSheet()
        shot("rhythm-sheet-top", tree: true)
        for i in 1...9 { scrollSheet(0.45); shot("rhythm-sheet-scroll-\(i)") }
        tap("Закрыть"); sleep(1)
        openRhythmSheet()
        pickFigure("шестнадцатая, шестнадцатая, восьмая")
        shot("after-16-16-8", tree: true)
        openRhythmSheet()
        shot("sheet-selected-16-16-8")
        pickFigure("Клаве сон 3-2")
        shot("after-clave", tree: true)
        // Clave in 3/4: is anything said?
        tap("4/4"); sleep(1)
        shot("meter-sheet-with-clave", tree: true)
        let minus = app.buttons.matching(NSPredicate(format: "label == 'Меньше'")).firstMatch
        if minus.exists { minus.tap(); usleep(600_000) }
        shot("meter-3-with-clave")
        tap("Закрыть"); sleep(1)
        shot("main-3-4-clave", tree: true)
        openRhythmSheet()
        pickFigure("Септоли")
        tap("3/4"); sleep(1)
        shot("meter-sheet-septuplets", tree: true)
        tap("Закрыть"); sleep(1)
    }

    // MARK: metronome — per-beat figure

    func testB_BeatFigure() {
        launch()
        openMetronome()
        tap("Доля 3, обычная"); usleep(300_000)
        shot("accent-menu", tree: true)
        sleep(3)
        shot("accent-menu-after-3s")
        // The menu stays open now (no 2.5 s timer): go straight to «Ритм доли».
        _ = tapContains("Ритм доли"); sleep(1)
        shot("beat3-sheet", tree: true)
        pickFigure("Триоли")
        shot("beat3-triplets", tree: true)
        // Common value change: does beat 3 keep its own?
        openRhythmSheet(); pickFigure("Восьмые")
        shot("common-eighths-beat3-triplets", tree: true)
        // Beat 4 figure then numerator 4 -> 3 -> 4 (zombie?)
        tapBegins("Доля 4"); usleep(200_000)
        _ = tapContains("Ритм доли"); sleep(1)
        pickFigure("шестнадцатая, шестнадцатая, восьмая")
        shot("beat4-16-16-8")
        tap("4/4"); sleep(1)
        let minus = app.buttons.matching(NSPredicate(format: "label == 'Меньше'")).firstMatch
        let plus = app.buttons.matching(NSPredicate(format: "label == 'Больше'")).firstMatch
        minus.tap(); usleep(600_000); plus.tap(); usleep(600_000)
        shot("meter-after-4-3-4", tree: true)
        // Деление 3 in the meter sheet: do beat figures stay?
        let three = app.buttons.matching(NSPredicate(format: "label == '3'")).firstMatch
        if three.exists { three.tap(); usleep(600_000) }
        shot("meter-subdivision-3")
        tap("Закрыть"); sleep(1)
        shot("main-after-meter", tree: true)
        // Reset beat 3
        tapBegins("Доля 3"); usleep(200_000)
        _ = tapContains("Ритм доли"); sleep(1)
        tap("Как у всех долей"); sleep(1)
        shot("beat3-reset", tree: true)
        // playing with figures: status line and strip
        tap("Старт"); sleep(2)
        shot("playing-beat-figures", tree: true)
        tap("Стоп"); sleep(1)
    }

    // MARK: metronome — figure with a rest on the beat

    func testC_RestOnBeatPlaying() {
        launch()
        openMetronome()
        openRhythmSheet()
        pickFigure("Восьмая на слабую")
        shot("offbeat-chosen", tree: true)
        tap("Старт")
        for i in 0..<4 { usleep(450_000); shot("offbeat-playing-\(i)", tree: i == 0) }
        tap("Стоп"); sleep(1)
        openRhythmSheet()
        pickFigure("Бэкбит 2 и 4")
        tap("Старт")
        for i in 0..<3 { usleep(500_000); shot("backbeat-playing-\(i)", tree: i == 0) }
        tap("Стоп"); sleep(1)
    }

    // MARK: metronome — ladder

    func testD_Ladder() {
        launch()
        openMetronome()
        openRhythmSheet(); pickFigure("шестнадцатая, шестнадцатая, восьмая")
        element("Темп").press(forDuration: 0.8); sleep(1)
        shot("modes-sheet", tree: true)
        tap("Лесенка делений"); sleep(1)
        shot("ladder-params")
        tap("Готово"); sleep(1)
        tap("Закрыть"); sleep(1)
        shot("main-ladder-on", tree: true)
        openRhythmSheet()
        shot("rhythm-sheet-ladder-hint", tree: true)
        tap("Закрыть"); sleep(1)
        tap("Старт"); sleep(2)
        shot("ladder-playing", tree: true)
        openRhythmSheet()
        pickFigure("Триоли")
        sleep(1)
        shot("ladder-playing-picked-triplets", tree: true)
        tap("Стоп"); sleep(1)
    }

    // MARK: metronome — presets

    func testE_Presets() {
        launch()
        openMetronome()
        openRhythmSheet(); pickFigure("шестнадцатая, шестнадцатая, восьмая")
        tap("Доля 2, обычная"); usleep(200_000)
        _ = tapContains("Ритм доли"); sleep(1)
        pickFigure("Триоли")
        tapBegins("Пресет:"); sleep(1)
        shot("presets-empty", tree: true)
        tap("Сохранить текущие"); sleep(1)
        shot("preset-name-alert", tree: true)
        tapIfExists("Сохранить")
        sleep(1)
        shot("presets-one", tree: true)
        tap("Закрыть"); sleep(1)
        shot("main-with-preset")
        openRhythmSheet(); pickFigure("Четверти")
        shot("main-preset-modified", tree: true)
        tapBegins("Пресет:"); sleep(1)
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'BPM'")).firstMatch
        if row.exists { row.tap(); sleep(1) }
        shot("main-preset-reloaded", tree: true)
    }

    // MARK: metronome — landscape

    func testF_Landscape() {
        launch()
        openMetronome()
        tap("Доля 2, обычная"); usleep(200_000)
        _ = tapContains("Ритм доли"); sleep(1)
        pickFigure("Триоли")
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        shot("land-main", tree: true)
        tapBegins("Доля 3"); usleep(300_000)
        shot("land-accent-menu", tree: true)
        dismissByDim()
        openRhythmSheet()
        shot("land-rhythm-sheet", tree: true)
        tapIfExists("Закрыть")
        element("Темп").press(forDuration: 0.8); sleep(1)
        shot("land-modes")
        tapIfExists("Закрыть")
        // minimum tempo: status line in landscape?
        let minus = element("Медленнее на 1")
        for _ in 0..<3 { minus.press(forDuration: 0.05) }
        XCUIDevice.shared.orientation = .portrait
        sleep(1)
    }

    // MARK: metronome — knob gesture

    func testG_Knob() {
        launch()
        openMetronome()
        let knob = element("Темп")
        let f = knob.frame
        log("knob frame \(f) start \(knobValue)")
        func drag(_ a: CGVector, _ b: CGVector, _ name: String) {
            let s = knob.coordinate(withNormalizedOffset: a), e = knob.coordinate(withNormalizedOffset: b)
            s.press(forDuration: 0.05, thenDragTo: e)
            usleep(600_000)
            log("\(name): \(knobValue)")
            shot("knob-\(name)")
        }
        drag(CGVector(dx: 0.5, dy: 0.15), CGVector(dx: 0.5, dy: 0.85), "vertical-down-through-centre")
        tap("Быстрее на 1")
        drag(CGVector(dx: 0.5, dy: 0.85), CGVector(dx: 0.5, dy: 0.15), "vertical-up-through-centre")
        drag(CGVector(dx: 0.3, dy: 0.5), CGVector(dx: 0.3, dy: 0.2), "up-on-left-side")
        drag(CGVector(dx: 0.7, dy: 0.5), CGVector(dx: 0.7, dy: 0.2), "up-on-right-side")
        drag(CGVector(dx: 0.2, dy: 0.5), CGVector(dx: 0.8, dy: 0.5), "horizontal-right")
        drag(CGVector(dx: 0.5, dy: 0.45), CGVector(dx: 0.5, dy: 0.6), "short-on-face")
        knob.doubleTap(); usleep(800_000)
        shot("knob-doubletap", tree: true)
        knob.doubleTap(); usleep(500_000)
    }

    // MARK: tuner and tunings

    func testH_Tuner() {
        launch()
        tab("Тюнер"); sleep(2)
        shot("tuner-main", tree: true)
        tapIfExists("Дополнительно"); sleep(1)
        shot("tuner-more", tree: true)
        dismissByDim()
        tapBegins("Струна"); sleep(1)
        shot("tuner-string-tap", tree: true)
        sleep(3)
        shot("tuner-after-ref")
        tapBegins("Строй:"); sleep(1)
        shot("tunings-sheet", tree: true)
        tapIfExists("Добавить строй"); sleep(1)
        shot("tunings-add", tree: true)
        tapIfExists("Генератором"); sleep(1)
        shot("generator", tree: true)
        scrollSheet(0.4)
        shot("generator-scrolled", tree: true)
        tapIfExists("Закрыть"); sleep(1)
        tapBegins("Строй:"); sleep(1)
        tapIfExists("Добавить строй"); sleep(1)
        tapIfExists("Из шаблона"); sleep(1)
        shot("library", tree: true)
        scrollSheet(0.5); shot("library-scrolled")
        tapIfExists("Закрыть"); sleep(1)
        tapBegins("Строй:"); sleep(1)
        tapBegins("Изменить строй"); sleep(1)
        shot("tuning-editor", tree: true)
        tapIfExists("Закрыть"); sleep(1)
        tapIfExists("Не сохранять"); sleep(1)
        tapBegins("Строй:"); sleep(1)
        let inst = app.buttons.matching(NSPredicate(format: "label CONTAINS 'струнн' AND NOT (label BEGINSWITH 'Строй')")).firstMatch
        if inst.exists { safeTap(inst); sleep(1) }
        shot("instrument", tree: true)
        scrollSheet(0.4); shot("instrument-scrolled", tree: true)
    }

    // MARK: settings, practice, onboarding

    func testI_SettingsPractice() {
        launch(["-metroPlay"])
        sleep(4)
        openMetronome(); sleep(2)
        tap("Стоп"); sleep(1)
        tab("Тюнер"); sleep(3)
        tab("Занятия"); sleep(1)
        shot("practice", tree: true)
        app.swipeUp(); sleep(1); shot("practice-scrolled", tree: true)
        tapIfExists("Настройки"); sleep(1)
        shot("settings", tree: true)
        app.swipeUp(); sleep(1); shot("settings-2", tree: true)
        app.swipeUp(); sleep(1); shot("settings-3", tree: true)
    }

    func testJ_Onboarding() {
        launch([], skipOnboarding: false)
        shot("onb-0", tree: true)
        for i in 1...4 {
            let next = app.buttons.matching(NSPredicate(format: "label IN {'Дальше', 'Далее', 'Начать', 'Готово', 'Продолжить'}")).firstMatch
            if !next.exists { break }
            safeTap(next); sleep(1); shot("onb-\(i)", tree: true)
        }
    }

    // MARK: accessibility under an open sheet

    func testK_SheetA11y() {
        launch()
        openMetronome()
        openRhythmSheet()
        let under = element("Старт")
        log("under sheet: Старт exists \(under.exists) hittable \(under.isHittable); tab Тюнер exists \(element("Тюнер", .button).exists)")
        shot("a11y-sheet", tree: true)
        tap("Закрыть")
        tab("Тюнер"); sleep(1)
        tapBegins("Строй:"); sleep(1)
        log("under tunings: dial exists \(element("Тюнер").exists)")
        shot("a11y-tunings", tree: true)
    }

    // MARK: journal with a real session

    func testL_Journal() {
        launch()
        openMetronome()
        tapBegins("Пресет:"); sleep(1)
        tap("Сохранить текущие"); sleep(1)
        tapIfExists("Сохранить"); sleep(1)
        tap("Закрыть"); sleep(1)
        tap("Старт")
        sleep(35)
        for _ in 0..<5 { tap("Быстрее на 1") }
        sleep(12)
        tap("Стоп"); sleep(1)
        tab("Занятия"); sleep(2)
        shot("journal", tree: true)
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'BPM'")).firstMatch
        if row.exists { safeTap(row); sleep(2); shot("journal-row-tap", tree: true) }
        openMetronome(); openRhythmSheet()
        log("under sheet (latest build): Старт exists \(element("Старт").exists)")
        shot("a11y-sheet-latest", tree: true)
    }
}
