import XCTest

final class TuningsTests: TruverUITestCase {
    func openTunings() {
        if !element("Инструмент и строи").exists { tapBegins("Строй:"); sleep(1) }
    }

    /// Simulator setup for screenshots of the boards: answers the microphone alert once (`simctl privacy grant`
    /// does not cover AVAudioApplication on the iOS 26 simulator).
    func testAllowMicrophone() {
        launch(["-tab", "tuner"])
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for title in ["Разрешить", "Allow"] where springboard.buttons[title].waitForExistence(timeout: 5) {
            springboard.buttons[title].tap(); break
        }
        sleep(1)
    }

    func testAddFromTemplateEditDelete() {
        launch(["-template", "g8-drop-e"])
        openTunings()
        tap("Добавить строй"); tap("Из библиотеки"); sleep(1)
        // open the card by tapping the row title
        tap("Стандарт F♯"); sleep(1)
        shot("template-card-or-row-tap", tree: true)
        if tapIfExists("Добавить в мои строи") { sleep(1); shot("added-from-card", tree: true) }
        openTunings()
        if element("Библиотека строев").exists {
            // still in library: use inline button
            let add = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Добавить '")).firstMatch
            if add.exists { add.tap(); sleep(1) }
            shot("library-inline-add", tree: true)
        }
        openTunings()
        shot("tunings-with-two", tree: true)
        // tuning editor of current
        tapBegins("Изменить строй"); sleep(1)
        shot("editor", tree: true)
        // tap + on the lowest string: what does it change?
        let plus = app.buttons.matching(NSPredicate(format: "label == 'Больше' OR label BEGINSWITH 'Выше'")).firstMatch
        if plus.exists { plus.tap(); usleep(500_000); plus.tap(); usleep(500_000) }
        shot("editor-plus-twice", tree: true)
        app.swipeUp(); shot("editor-scrolled", tree: true)
        tap("Закрыть"); sleep(1)
        shot("editor-close-unsaved", tree: true)
        tapIfExists("Не сохранять"); sleep(1)
        openTunings()
        shot("tunings-after-editor", tree: true)
        // swipe left on second row
        let rowTitle = app.staticTexts.matching(NSPredicate(format: "label == 'Стандарт F♯' OR label == 'Стандарт F#'")).firstMatch
        if rowTitle.exists {
            let y = rowTitle.frame.midY
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(CGVector(dx: 330, dy: y))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(CGVector(dx: 60, dy: y))
            start.press(forDuration: 0.05, thenDragTo: end)
            sleep(1)
        }
        shot("swiped-row", tree: true)
        tapIfExists("Удалить"); sleep(1)
        shot("delete-confirm", tree: true)
        tapIfExists("Удалить"); sleep(1)
        shot("after-delete", tree: true)
    }

    func testCopyCurrentThenClose() {
        launch(["-template", "g7-standard-b"])
        openTunings()
        tap("Добавить строй"); tap("Вручную"); sleep(1)
        shot("copy-editor", tree: true)
        tap("Закрыть"); sleep(1)
        shot("copy-closed", tree: true)
        openTunings()
        shot("tunings-after-copy-close", tree: true)
    }

    func testInstrumentEditor() {
        launch(["-template", "g8-drop-e"])
        openTunings()
        tap("8-струнная гитара"); sleep(1)
        shot("instrument-editor", tree: true)
        app.swipeUp(); shot("instrument-editor-scrolled", tree: true)
        tapBegins("Калибры"); sleep(1); shot("instrument-strings", tree: true)
        app.swipeUp(); shot("instrument-strings-scrolled")
        tapIfExists("Назад") || tapIfExists("Закрыть"); sleep(1)
        shot("after-strings-back", tree: true)
        if !element("Инструмент").exists { openTunings(); tap("8-струнная гитара"); sleep(1) }
        app.swipeDown()
        // string count +
        let plus = app.buttons.matching(NSPredicate(format: "label == 'Больше'")).firstMatch
        if plus.exists { plus.tap(); sleep(1) }
        shot("strings-plus-rebuild", tree: true)
        app.swipeUp(); shot("rebuild-scrolled")
        tapIfExists("Отмена") || tapIfExists("Закрыть"); sleep(1)
        shot("rebuild-cancel", tree: true)
        tapIfExists("Капо"); sleep(1); shot("capo-menu", tree: true)
        tapIfExists("3-й лад"); sleep(1); shot("capo-3")
        tapIfExists("Готово"); sleep(1)
        tab("Гриф"); sleep(1); shot("fretboard-with-capo3", tree: true)
        tab("Тюнер"); sleep(1); shot("tuner-with-capo3", tree: true)
    }
}
