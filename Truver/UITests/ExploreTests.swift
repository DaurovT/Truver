import XCTest

/// Pass 0: dump every tab's accessibility tree to learn labels.
final class ExploreTests: TruverUITestCase {
    func testDumpTabs() {
        launch(["-template", "g8-drop-e"])
        app.tap() // trigger interruption monitor if any
        shot("tuner", tree: true)
        tab("Гриф"); sleep(1); shot("fretboard", tree: true)
        tab("Метроном"); sleep(1); shot("metronome", tree: true)
        tab("Занятия"); sleep(1); shot("practice", tree: true)
        tab("Тюнер"); sleep(1)
        tapBegins("Строй:"); sleep(1); shot("tunings-sheet", tree: true)
    }
}
