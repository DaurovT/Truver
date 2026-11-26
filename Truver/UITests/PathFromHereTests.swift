import XCTest

/// «Путь отсюда»: what the user sees after choosing it from the note menu.
final class PathFromHereTests: TruverUITestCase {
    func neck() -> XCUIElement { elementBegins("Гриф,") }

    func testPathFromHere() {
        launch(["-template", "g8-standard-fs", "-tab", "fretboard"])
        shot("before", tree: true)
        neck().coordinate(withNormalizedOffset: CGVector(dx: 0.36, dy: 0.55)).press(forDuration: 1.0)
        sleep(1)
        shot("menu", tree: true)
        tap("Путь отсюда"); usleep(800_000)
        shot("path-toast")
        sleep(3)
        shot("path", tree: true)
        neck().swipeUp(); sleep(1)
        shot("path-scrolled")
        tap("Сыграть путь"); sleep(3)
        shot("path-playing", tree: true)
        tapIfExists("Пауза"); sleep(1)
        tap("Путь по грифу"); sleep(1)
        shot("path-sheet", tree: true)
    }
}
