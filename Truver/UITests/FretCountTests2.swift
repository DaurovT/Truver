import XCTest

final class FretCountEditorTests: TruverUITestCase {
    func testFretsInTuningEditor() {
        launch(["-template", "g7-standard-b", "-tab", "tuner"])
        tapBegins("Строй:"); sleep(1)
        tapBegins("Изменить строй"); sleep(1)
        app.swipeUp(); sleep(1)
        shot("editor", tree: true)
        tap("Ладов"); sleep(1)
        shot("frets-menu", tree: true)
        tap("22 лада"); sleep(1)
        shot("frets-22", tree: true)
    }
}
