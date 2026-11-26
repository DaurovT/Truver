import XCTest

final class FretboardTests: TruverUITestCase {
    func open(_ extra: [String] = []) {
        launch(["-template", "g8-drop-e", "-tab", "fretboard"] + extra)
        app.tap(); sleep(1)
    }

    func neck() -> XCUIElement { elementBegins("Гриф,") }

    func testScaleSheetAndView() {
        open()
        shot("fretboard-start", tree: true)
        tapBegins("Гамма:"); sleep(1)
        shot("scale-sheet", tree: true)
        app.swipeUp(); shot("scale-sheet-scrolled", tree: true)
        // choose another scale
        let dorian = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'дор'")).firstMatch
        if dorian.exists { dorian.tap(); sleep(1) } else { tapIfExists("Закрыть") }
        shot("after-scale-pick", tree: true)
        if element("Гамма").exists && element("Закрыть").exists { tap("Закрыть") }
        shot("fretboard-new-scale", tree: true)
        tapIfExists("Сбросить изменения"); shot("after-reset")
        tap("Вид и подписи"); sleep(1)
        shot("view-sheet", tree: true)
        tapIfExists("Ступени"); shot("labels-degrees")
        tapIfExists("Низкая струна снизу"); shot("low-string-toggle")
        tap("Закрыть"); sleep(1)
        shot("fretboard-after-view-change")
    }

    func testPositionsAndPlay() {
        open()
        tap("Следующая позиция"); shot("pos-next1", tree: true)
        tap("Следующая позиция"); shot("pos-next2")
        tap("Предыдущая позиция"); shot("pos-prev")
        for _ in 0..<12 { element("Следующая позиция").tap(); usleep(200_000) }
        shot("pos-many-next", tree: true)
        tap("Сыграть гамму"); sleep(2)
        shot("playing", tree: true)
        sleep(2); shot("playing-later")
        tapIfExists("Пауза"); shot("paused", tree: true)
        tap("Настройки проигрывания"); sleep(1)
        shot("play-settings", tree: true)
        app.swipeUp(); shot("play-settings-scrolled")
        tap("Закрыть")
    }

    func testChordsStrip() {
        open()
        let chords = app.buttons.matching(NSPredicate(format: "label CONTAINS ', I' OR label CONTAINS ', V' OR label CONTAINS ', i' OR label CONTAINS ', v'"))
        shot("before-chord", tree: true)
        if chords.count > 0 { chords.element(boundBy: 0).tap(); sleep(1) }
        shot("chord-selected", tree: true)
        if chords.count > 0 { chords.element(boundBy: 0).tap(); sleep(1) }
        shot("chord-deselected")
        if chords.count > 4 { chords.element(boundBy: 4).tap(); sleep(1) }
        shot("chord-5-selected")
    }

    func testModes() {
        open()
        tap("Аккорд"); sleep(1); shot("mode-chord", tree: true)
        tapIfExists("Следующее расположение"); shot("chord-next-voicing")
        tapIfExists("Все аккорды"); sleep(1); shot("all-chords", tree: true)
        tapIfExists("Закрыть"); sleep(1)
        tap("Поиск"); sleep(1); shot("mode-search", tree: true)
        // tap three notes on the neck
        let n = neck()
        if n.exists {
            for p in [(0.3, 0.2), (0.5, 0.25), (0.7, 0.3), (0.4, 0.35)] { n.coordinate(withNormalizedOffset: CGVector(dx: p.0, dy: p.1)).tap(); usleep(400_000) }
        }
        shot("search-marked", tree: true)
        let res = app.buttons.matching(NSPredicate(format: "label CONTAINS 'ноты'")).firstMatch
        if res.exists { res.tap(); sleep(1) }
        shot("search-results", tree: true)
        tapIfExists("Закрыть"); sleep(1)
        tap("Гамма"); sleep(1); shot("mode-scale-back")
    }

    func testLongPressMenu() {
        open()
        let n = neck()
        XCTAssert(n.waitForExistence(timeout: 3))
        n.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.3)).press(forDuration: 1.0)
        sleep(1)
        shot("note-menu", tree: true)
        tapIfExists("Аккорды от этой ноты"); sleep(1)
        shot("chords-from-note", tree: true)
        app.swipeUp(); shot("chords-from-note-scrolled")
        tapIfExists("Закрыть"); sleep(1)
        n.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.3)).press(forDuration: 1.0); sleep(1)
        tapIfExists("Гамма от этой ноты"); sleep(1)
        shot("scale-from-note", tree: true)
        tapIfExists("Закрыть"); sleep(1)
        n.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.3)).press(forDuration: 1.0); sleep(1)
        tapIfExists("Прогрессия отсюда"); usleep(500_000)
        shot("progression-toast")
        sleep(2)
        n.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.3)).press(forDuration: 1.0); sleep(1)
        tapIfExists("Путь отсюда"); sleep(1)
        shot("path-mode", tree: true)
        tapIfExists("Путь по грифу"); sleep(1); shot("path-sheet", tree: true)
        tapIfExists("Закрыть"); sleep(1)
        tapIfExists("Сыграть путь"); sleep(2); shot("path-playing")
        tapIfExists("Пауза")
        tapIfExists("Выйти из пути"); sleep(1); shot("path-exit")
    }

    func testCustomWindow() {
        open()
        let pos = elementBegins("Позиция")
        let target = pos.exists ? pos : app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'лады'")).firstMatch
        if target.exists { target.press(forDuration: 1.0); sleep(1) }
        shot("window-edit", tree: true)
        tapIfExists("Готово"); sleep(1); shot("window-done")
    }

    func testLandscape() {
        open()
        XCUIDevice.shared.orientation = .landscapeLeft; sleep(2)
        shot("landscape", tree: true)
        XCUIDevice.shared.orientation = .portrait; sleep(1)
    }
}
