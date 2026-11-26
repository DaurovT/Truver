import XCTest

final class MetronomeTests: TruverUITestCase {
    func open() { launch(["-tab", "metronome"]); app.tap(); sleep(1) }

    func testStartStopTempo() {
        open()
        shot("metronome-start", tree: true)
        tap("Быстрее на 1"); tap("Быстрее на 1"); shot("plus2")
        tap("Медленнее на 1"); shot("minus1")
        tap("Старт"); sleep(2); shot("playing", tree: true)
        tab("Тюнер"); sleep(1); shot("tuner-while-metronome", tree: true)
        tab("Метроном"); sleep(1)
        tap("Стоп"); shot("stopped")
        let t = element("Tap tempo — стучите в ритм")
        for _ in 0..<5 { t.tap(); usleep(500_000) }
        shot("tap-tempo-120ish", tree: true)
        // drag knob
        let knob = element("Темп")
        if knob.exists { knob.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).press(forDuration: 0.1, thenDragTo: knob.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))) }
        shot("knob-drag", tree: true)
        // long press minus to the bottom bound
        let minus = element("Медленнее на 1"); minus.press(forDuration: 3); shot("minus-held")
    }

    func testAccentsAndMeter() {
        open()
        tapBegins("Доля 2"); sleep(1); shot("accent-beat2", tree: true)
        tapBegins("Доля 2"); sleep(1); shot("accent-beat2-again")
        dismissByDim(); shot("accent-dismiss")
        let strip = elementBegins("Доли ")
        if strip.exists { strip.press(forDuration: 1.0); sleep(1) }
        shot("meter-sheet", tree: true)
        app.swipeUp(); shot("meter-sheet-scrolled", tree: true)
        tapIfExists("Закрыть"); sleep(1)
    }

    func testPresetsModesSoundsTimer() {
        open()
        tapBegins("Пресет"); sleep(1); shot("presets", tree: true)
        tapIfExists("Сохранить текущие"); sleep(1); shot("preset-save", tree: true)
        tapIfExists("Сохранить"); sleep(1); shot("preset-saved", tree: true)
        tapIfExists("Закрыть"); sleep(1)
        shot("after-presets", tree: true)
        // chips row
        let chips = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Режим' OR label CONTAINS 'Таймер' OR label CONTAINS 'Размер' OR label CONTAINS 'Звук'"))
        let n = chips.count
        var labels: [String] = []
        for i in 0..<n { labels.append(chips.element(boundBy: i).label) }
        let a = XCTAttachment(string: labels.joined(separator: "\n")); a.lifetime = .keepAlways; a.name = "chips"; add(a)
        let knob = element("Темп")
        if knob.exists { knob.press(forDuration: 1.0); sleep(1) }
        shot("modes-sheet", tree: true)
        tapIfExists("Разгон"); sleep(1); shot("mode-ramp", tree: true)
        app.swipeUp(); shot("mode-ramp-scrolled")
        tapIfExists("Готово"); tapIfExists("Закрыть"); sleep(1)
        shot("after-modes", tree: true)
        tap("Старт"); sleep(3); shot("playing-with-mode", tree: true)
        tap("Стоп")
        tapIfExists("Таймер занятия"); sleep(1); shot("timer-sheet", tree: true)
        tapIfExists("Закрыть"); sleep(1)
        tap("Настройки"); sleep(1); shot("settings-from-metronome", tree: true)
    }
}
