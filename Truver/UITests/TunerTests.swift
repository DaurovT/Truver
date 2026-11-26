import XCTest

final class TunerTests: TruverUITestCase {
    func testModesAndStrings() {
        launch(["-template", "g8-drop-e", "-tab", "tuner"])
        app.tap(); sleep(1)
        shot("tuner-start", tree: true)
        tap("Ручной"); shot("manual")
        tapBegins("Струна "); shot("manual-string-tapped", tree: true)
        // tap same string again (should return to auto per PRD)
        tapBegins("Струна "); shot("string-tapped-again")
        tap("Хром."); shot("chromatic")
        tap("Авто"); shot("auto")
        // tap last string button (highest)
        let strings = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Струна '"))
        if strings.count > 1 { strings.element(boundBy: strings.count - 1).tap(); usleep(700_000) }
        shot("auto-tap-high-string")
    }

    func testReferenceTone() {
        launch(["-template", "g8-drop-e", "-tab", "tuner"])
        app.tap(); sleep(1)
        tap("Эталонный тон"); usleep(400_000)
        shot("reference-playing", tree: true)
        sleep(3); shot("reference-after-3s")
        tapIfExists("Эталонный тон"); shot("reference-tapped-again")
    }

    func testProPanelAndInput() {
        launch(["-template", "g8-drop-e", "-tab", "tuner"])
        app.tap(); sleep(1)
        tap("Дополнительно")
        shot("pro-panel", tree: true)
        app.swipeUp(); shot("pro-panel-scrolled")
        tapBegins("A4 этого строя"); sleep(1)
        shot("pro-a4-opens-editor", tree: true)
        tapIfExists("Закрыть"); sleep(1); shot("after-close-editor")
        tapBegins("Вход:"); sleep(1); shot("input-chip-tapped", tree: true)
    }
}

final class TunerExtraTests: TruverUITestCase {
    func testReferenceCountdown() {
        launch(["-template", "g8-drop-e", "-tab", "tuner"])
        tap("Ручной")
        let strings = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Струна '"))
        strings.element(boundBy: strings.count - 1).tap(); usleep(500_000)
        shot("manual-high-e", tree: true)
        tap("Эталонный тон")
        shot("ref-t0", tree: true)
        sleep(1); shot("ref-t1")
        sleep(1); shot("ref-t2")
        sleep(3); shot("ref-t5", tree: true)
        // touch something unrelated to force a redraw
        tap("Ручной"); shot("ref-after-redraw", tree: true)
    }

    func testProPanelA4Return() {
        launch(["-template", "g8-drop-e", "-tab", "tuner"])
        tap("Дополнительно")
        tap("Ближайшая ступень"); shot("target-nearest", tree: true)
        tapBegins("A4 этого строя"); sleep(1)
        app.swipeUp(); shot("editor-scrolled-a4", tree: true)
        tapIfExists("A4"); sleep(1); shot("a4-row-tapped", tree: true)
    }
}
