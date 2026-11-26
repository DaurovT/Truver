import XCTest

/// Exploratory critic pass over «Гриф» (real taps). Screenshots only; no assertions beyond existence.
final class FretboardCriticTests: TruverUITestCase {
    func open(_ template: String = "g8-drop-e", _ extra: [String] = []) {
        launch(["-template", template, "-tab", "fretboard", "-resetFretboard"] + extra)
        sleep(1)
    }

    func neck() -> XCUIElement { elementBegins("Гриф,") }

    func pressNeck(_ x: Double, _ y: Double, _ d: Double = 1.0) {
        neck().coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).press(forDuration: d)
        sleep(1)
    }

    func tapNeck(_ x: Double, _ y: Double) {
        neck().coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
        usleep(600_000)
    }

    // 1. Scale mode: sheets, positions, whole neck, custom window, chord strip, playback.
    func testA_Scale() {
        open()
        shot("start", tree: true)
        tapBegins("Гамма:"); sleep(1); shot("scale-sheet", tree: true)
        tapIfExists("A"); shot("scale-sheet-A")
        let field = app.textFields.firstMatch
        if field.exists { field.tap(); field.typeText("дор"); sleep(1); shot("scale-search-dor", tree: true)
            field.typeText("zzz"); sleep(1); shot("scale-search-nothing")
        }
        tapIfExists("Закрыть"); sleep(1); shot("after-scale-sheet")
        tap("Вид и подписи"); sleep(1); shot("view-sheet", tree: true)
        tapIfExists("Ящики"); tapIfExists("Интерв."); shot("view-boxes-intervals")
        tapIfExists("Закрыть"); sleep(1); shot("neck-boxes-intervals")
        tap("Вид и подписи"); sleep(1); tapIfExists("Пальцы"); tapIfExists("Закрыть"); sleep(1); shot("neck-fingers")
        tap("Вид и подписи"); sleep(1); tapIfExists("3 ноты на струну"); tapIfExists("Ноты"); tapIfExists("Закрыть"); sleep(1)
        tap("Следующая позиция"); shot("pos-2", tree: true)
        for _ in 0..<20 { element("Следующая позиция").tap(); usleep(150_000) }
        shot("pos-last")
        let pos = elementBegins("Позиция")
        if pos.exists { safeTap(pos) } else { app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Позиция'")).firstMatch.tap() }
        sleep(1); shot("whole-neck", tree: true)
        neck().swipeUp(); sleep(1); shot("whole-neck-scrolled")
        tap("Следующая позиция"); shot("from-whole-next")
        let label = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Позиция' OR label BEGINSWITH 'Весь'")).firstMatch
        if label.exists { label.press(forDuration: 1.2) }
        sleep(1); shot("window-edit", tree: true)
        tapIfExists("Готово"); sleep(1); shot("window-done")
        // Chord strip
        let chords = app.buttons.matching(NSPredicate(format: "label CONTAINS ', I' OR label CONTAINS ', V' OR label CONTAINS ', i' OR label CONTAINS ', v'"))
        if chords.count > 3 { chords.element(boundBy: 3).tap(); usleep(300_000); shot("chord-strip-iv") }
        tap("Аккорд"); sleep(1); shot("chord-mode-after-strip")
        tap("Гамма"); sleep(1)
        tap("Настройки проигрывания"); sleep(1); shot("play-sheet", tree: true)
        tapIfExists("Закрыть"); sleep(1)
        tap("Сыграть гамму"); sleep(3); shot("playing")
        tapIfExists("Пауза"); sleep(1); shot("paused", tree: true)
    }

    // 2. Path: entry button, sheet, variants, play, manual scroll, exit.
    /// FB-26: the chord picked in the strip opens in «Аккорд»; without a pick — the chord of the first degree.
    func testI_ScaleToChord() {
        open()
        tap("Аккорд"); sleep(1); shot("no-pick", tree: true)
        tap("Гамма"); sleep(1)
        let chords = app.buttons.matching(NSPredicate(format: "label CONTAINS ', IV' OR label CONTAINS ', iv'"))
        if chords.count > 0 { chords.firstMatch.tap(); usleep(400_000); shot("strip-iv", tree: true) }
        tap("Аккорд"); sleep(1); shot("after-strip", tree: true)
    }

    /// Capo: positions start at the capo, frets are counted from it.
    func testJ_Capo() {
        open("g6-standard-e", ["-capo", "3"])
        shot("capo-3", tree: true)
        tap("Следующая позиция"); usleep(500_000); shot("capo-next")
    }

    /// Note menu (dim + big note), scale from the note with a preview, the built position.
    func testK_FromNote() {
        open("g6-standard-e")
        pressNeck(0.30, 0.55); shot("menu-dim", tree: true)
        tapIfExists("Гамма от этой ноты"); sleep(1); shot("preview", tree: true)
        tapIfExists("Построить гамму"); sleep(1); shot("built", tree: true)
    }

    /// Own window: the frets around it stay visible.
    func testL_Window() {
        open("g8-drop-e")
        let view = elementBegins("Вид грифа")
        if view.exists { view.tap(); usleep(500_000); shot("view-menu") }
        tapIfExists("Своё окно ладов…"); sleep(1); shot("window-edit", tree: true)
    }

    /// Progression: editor, insert, any chord, save under a name, beat dots.
    func testM_Progression() {
        open("g6-standard-e")
        tap("Прогрессия"); sleep(1); shot("start", tree: true)
        let second = elementBegins("Такт 2")
        second.tap(); usleep(500_000); second.tap(); sleep(1); shot("editor", tree: true)
        tapIfExists("после"); sleep(1); shot("insert-sheet", tree: true)
        tapIfExists("Любой аккорд"); usleep(500_000); shot("any-chord", tree: true)
        let put = elementBegins("Поставить")
        if put.exists { put.tap(); sleep(1) }
        shot("after-insert", tree: true)
        let menu = elementBegins("Прогрессия:")
        if menu.exists { menu.tap(); usleep(600_000); shot("menu") }
        tapIfExists("Сохранить как…"); usleep(600_000)
        let field = app.textFields.firstMatch
        if field.waitForExistence(timeout: 2) { field.tap(); field.typeText("Riff A") }
        usleep(300_000); shot("name-alert")
        tapIfExists("Сохранить"); sleep(1); shot("saved", tree: true)
        tapIfExists("Сыграть прогрессию"); usleep(2_600_000); shot("playing-beats")
        tapIfExists("Стоп"); sleep(1); shot("stopped")
    }

    func testB_Path() {
        open()
        tap("Путь по грифу"); sleep(1); shot("path-sheet", tree: true)
        tapIfExists("4 ноты наискосок"); sleep(1); shot("path-sheet-4diag")
        tapIfExists("Закрыть"); sleep(1); shot("path-4diag", tree: true)
        tapIfExists("Сыграть путь"); sleep(4); shot("path-playing")
        neck().swipeDown(); sleep(1); shot("path-manual-scroll", tree: true)
        tapIfExists("К текущей ноте"); sleep(1); shot("path-back-to-current")
        tapIfExists("Пауза"); sleep(1); shot("path-paused", tree: true)
        tapIfExists("Путь по грифу"); sleep(1); tapIfExists("По одной струне"); tapIfExists("Закрыть"); sleep(1); shot("path-one-string")
        tapIfExists("Путь по грифу"); sleep(1); tapIfExists("3 ноты на струну"); tapIfExists("Закрыть"); sleep(1); shot("path-3ps")
        tap("Аккорд"); sleep(1); shot("path-then-chord")
        tap("Гамма"); sleep(1); shot("path-then-scale", tree: true)
        if element("Выйти из пути").exists { tap("Выйти из пути"); sleep(1); shot("path-exited") }
    }

    // 3. Note menu and its items.
    func testC_NoteMenu() {
        open()
        shot("before", tree: true)
        pressNeck(0.5, 0.35); shot("menu", tree: true)
        tapIfExists("Гамма от этой ноты"); sleep(1); shot("scale-from-note", tree: true)
        tapIfExists("Все гаммы"); sleep(1); shot("scale-from-note-all", tree: true)
        tapIfExists("Закрыть"); sleep(1); shot("after-all-close")
        pressNeck(0.5, 0.35); tapIfExists("Гамма от этой ноты"); sleep(1)
        tapIfExists("Построить гамму"); sleep(1); shot("scale-built", tree: true)
        pressNeck(0.5, 0.35); tapIfExists("Аккорды от этой ноты"); sleep(1); shot("chords-from-note", tree: true)
        let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS 'удобно' OR label CONTAINS 'растяжка'"))
        if rows.count > 0 { rows.element(boundBy: 0).tap(); sleep(1) }
        shot("chords-from-note-picked", tree: true)
        tapIfExists("Закрыть"); sleep(1); shot("after-chords-close")
        pressNeck(0.5, 0.35); tapIfExists("Скрыть ноту"); sleep(1); shot("note-hidden", tree: true)
        pressNeck(0.5, 0.35); shot("menu-on-hidden", tree: true)
        tapIfExists("Добавить ноту") || tapIfExists("Скрыть ноту"); sleep(1); shot("after-second-toggle")
        pressNeck(0.5, 0.35); tapIfExists("Прогрессия отсюда"); sleep(1); shot("progression-from-here", tree: true)
        tap("Гамма"); sleep(1)
        pressNeck(0.5, 0.35); tapIfExists("Путь отсюда"); sleep(1); shot("path-from-here", tree: true)
    }

    // 4. Chord mode.
    func testD_Chord() {
        open()
        tap("Аккорд"); sleep(1); shot("chord", tree: true)
        tapIfExists("maj7"); sleep(1); shot("maj7")
        tap("Следующее расположение"); shot("voicing-2")
        tap("Следующее расположение"); shot("voicing-3")
        let inv = app.buttons.matching(NSPredicate(format: "label CONTAINS '/'")).firstMatch
        if inv.exists { inv.tap(); sleep(1) }
        shot("inversion", tree: true)
        tapIfExists("Гаммы ›"); sleep(1); shot("library-scales", tree: true)
        tapIfExists("Назад"); sleep(1)
        tap("Все аккорды"); sleep(1); shot("library", tree: true)
        app.swipeUp(); sleep(1); shot("library-scrolled")
        tapIfExists("ещё…"); sleep(1); shot("library-all-types", tree: true)
        let t = element("13♯11")
        if t.exists { safeTap(t); sleep(1); shot("library-13s11") }
        tapIfExists("Назад"); sleep(1); shot("chord-after-library")
        tapIfExists("Сыграть"); sleep(1); shot("chord-played")
        pressNeck(0.5, 0.4); shot("chord-longpress")
    }

    // 5. Search mode.
    func testE_Search() {
        open()
        tap("Поиск"); sleep(1); shot("search-empty", tree: true)
        tapNeck(0.12, 0.62); shot("mark1")
        tapNeck(0.30, 0.45); shot("mark2")
        tapNeck(0.45, 0.45); shot("mark3", tree: true)
        tapNeck(0.60, 0.30); shot("mark4", tree: true)
        tapIfExists("Гаммы с этими нотами ›"); sleep(1); shot("results-sheet", tree: true)
        tapIfExists("Закрыть"); sleep(1)
        tapIfExists("Открыть в «Аккорде»"); sleep(1); shot("opened-in-chord", tree: true)
        tap("Поиск"); sleep(1); shot("back-to-search")
        tapIfExists("Сбросить"); sleep(1); shot("search-reset")
        // chromatic cluster: three adjacent frets on three strings
        tapNeck(0.2, 0.3); tapNeck(0.35, 0.42); tapNeck(0.5, 0.55); tapNeck(0.65, 0.3); shot("cluster", tree: true)
    }

    // 6. Progression.
    func testF_Progression() {
        open()
        tap("Прогрессия"); sleep(1); shot("progression", tree: true)
        tapBegins("Тональность"); sleep(1); shot("key-menu", tree: true)
        tapIfExists("G"); sleep(1); shot("key-G")
        tapBegins("Прогрессия:"); sleep(1); shot("template-menu", tree: true)
        let items = app.buttons.matching(NSPredicate(format: "label CONTAINS '–'"))
        if items.count > 2 { items.element(boundBy: 2).tap(); sleep(1) } else { dismissByDim() }
        shot("template-3", tree: true)
        let cards = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Такт'"))
        if cards.count > 1 { cards.element(boundBy: 1).tap(); sleep(1); shot("ribbon-2")
            cards.element(boundBy: 1).tap(); sleep(1); shot("chord-editor", tree: true)
            app.swipeUp(); sleep(1); shot("chord-editor-scrolled")
            tapIfExists("Закрыть"); sleep(1) }
        tapIfExists("Добавить аккорд"); sleep(1); shot("add-chord", tree: true)
        tapIfExists("Закрыть"); sleep(1)
        tap("Ритм"); sleep(1); shot("rhythm-sheet", tree: true)
        tapIfExists("Закрыть"); sleep(1)
        tapIfExists("Сыграть прогрессию"); sleep(4); shot("prog-playing", tree: true)
        tapIfExists("Стоп"); sleep(1); shot("prog-stopped")
        tapIfExists("Окно выше"); sleep(1); shot("window-shift")
    }

    // 7. Landscape in every mode.
    func testG_Landscape() {
        open()
        XCUIDevice.shared.orientation = .landscapeLeft; sleep(2)
        shot("land-scale", tree: true)
        let chip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Вид:'")).firstMatch
        if chip.exists { chip.tap(); sleep(1); shot("land-view-menu", tree: true)
            tapIfExists("Весь гриф"); sleep(1); shot("land-whole") }
        pressNeck(0.4, 0.4); shot("land-note-menu", tree: true)
        tapIfExists("Путь отсюда"); sleep(1); shot("land-path", tree: true)
        tapIfExists("Назад"); sleep(1)
        XCUIDevice.shared.orientation = .portrait; sleep(2)
        tap("Аккорд"); sleep(1)
        XCUIDevice.shared.orientation = .landscapeLeft; sleep(2); shot("land-chord", tree: true)
        XCUIDevice.shared.orientation = .portrait; sleep(2)
        tap("Поиск"); sleep(1)
        XCUIDevice.shared.orientation = .landscapeLeft; sleep(2); shot("land-search", tree: true)
        XCUIDevice.shared.orientation = .portrait; sleep(2)
        tap("Прогрессия"); sleep(1)
        XCUIDevice.shared.orientation = .landscapeLeft; sleep(2); shot("land-progression", tree: true)
        XCUIDevice.shared.orientation = .portrait; sleep(2)
    }

    // 8. Density: 9 strings, bass, 6 strings, left-handed.
    func testH_Density() {
        open("g9-standard-b")
        shot("g9-position", tree: true)
        tap("Аккорд"); sleep(1); shot("g9-chord")
        tap("Гамма"); sleep(1)
        open("b4-standard")
        shot("bass-position", tree: true)
        tap("Аккорд"); sleep(1); shot("bass-chord", tree: true)
        tap("Гамма"); sleep(1)
        tap("Путь по грифу"); sleep(1); tapIfExists("Закрыть"); sleep(1); shot("bass-path")
        open("g6-standard-e")
        shot("g6-position", tree: true)
        tap("Вид и подписи"); sleep(1)
        let lefty = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Для левши'"))
        if lefty.count > 0 { safeTap(lefty.element(boundBy: lefty.count - 1)); sleep(1) }
        tapIfExists("Закрыть"); sleep(1); shot("g6-lefty")
        open("g8-drop-e")
        shot("restored-g8")
    }
}
