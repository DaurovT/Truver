import XCTest

/// Reproduces «Путь отсюда» as the user sees it: portrait and landscape, scrolled, playing.
final class PathOnPhoneTests: TruverUITestCase {
    func neck() -> XCUIElement { elementBegins("Гриф,") }

    func testPathPortraitAndLandscape() {
        XCUIDevice.shared.orientation = .portrait
        launch(["-template", "g8-standard-fs", "-tab", "fretboard"])
        shot("start", tree: true)
        neck().coordinate(withNormalizedOffset: CGVector(dx: 0.36, dy: 0.55)).press(forDuration: 1.0)
        sleep(1)
        tap("Путь отсюда"); sleep(4)
        shot("portrait-path", tree: true)
        tap("Сыграть путь"); sleep(4)
        shot("portrait-playing", tree: true)
        tapIfExists("Пауза"); sleep(1)
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(3)
        shot("landscape-path", tree: true)
        let play = app.buttons.matching(NSPredicate(format: "label == 'Сыграть'")).firstMatch
        if play.exists { play.tap(); sleep(4); shot("landscape-playing", tree: true) }
        XCUIDevice.shared.orientation = .portrait
        sleep(2)
        // The other entry: «Путь» button in the scale row.
        tapIfExists("Выйти из пути"); sleep(1)
        tapIfExists("Путь по грифу"); sleep(2)
        shot("path-button", tree: true)
        tapIfExists("Закрыть"); sleep(2)
        shot("path-button-neck", tree: true)
        tapIfExists("Выйти из пути"); sleep(1)
        tapBegins("Вид грифа"); sleep(1)
        tapIfExists("Весь гриф"); sleep(2)
        shot("whole-neck-portrait", tree: true)
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(3)
        shot("whole-neck-landscape", tree: true)
        XCUIDevice.shared.orientation = .portrait
        sleep(1)
    }
}
