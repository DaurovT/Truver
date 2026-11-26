import XCTest

/// Stage SM «Проверка игры»: the chip, the settings sheet and the attempt summary render.
final class PlayCheckTests: TruverUITestCase {
    func testSheets() {
        launch(["-tab", "metronome", "-sheet", "playCheckSummary"])
        sleep(3)
        shot("summary", tree: true)
        tapIfExists("Готово"); sleep(1)
        tapIfExists("Проверка игры"); sleep(1)
        shot("settings", tree: true)
    }

    func testTrainingLayout() {
        launch(["-tab", "fretboard", "-template", "g8-standard-fs", "-trainingDemo"])
        sleep(3)
        shot("training", tree: true)
    }

    func testCharts() {
        launch(["-tab", "practice", "-playCheckHistoryDemo"])
        sleep(3)
        shot("charts", tree: true)
        app.swipeUp(); sleep(1)
        shot("charts-scrolled")
    }

    func testSession() {
        launch(["-tab", "practice"])
        tapBegins("Занятие"); sleep(2)
        shot("session-editor", tree: true)
        // No microphone and no voice in the simulator (the Mac would hear and speak).
        for label in ["Проверка игры", "Голосовые подсказки"] {
            let sw = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label))
            if sw.count > 0 { safeTap(sw.element(boundBy: sw.count - 1)); sleep(1) }
        }
        shot("session-editor-off", tree: true)
        tapIfExists("Начать занятие"); sleep(3)
        shot("session-running", tree: true)
        tapIfExists("Закончить"); sleep(2)
        shot("session-summary", tree: true)
    }

    func testHowItWorks() {
        launch(["-tab", "metronome", "-sheet", "playCheck"])
        sleep(2)
        shot("how", tree: true)
    }
}
