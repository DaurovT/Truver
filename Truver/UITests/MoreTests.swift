import XCTest

final class MetronomeMoreTests: TruverUITestCase {
    func testMeterLongPressAndPresets() {
        launch(["-tab", "metronome"])
        let strip = elementBegins("Доли ")
        // long-press on the gap left of beat 1 (still inside the strip)
        let b1 = elementBegins("Доля 1")
        b1.press(forDuration: 1.2); sleep(1)
        shot("longpress-beat1", tree: true)
        if !element("Размер и деление").exists { dismissByDim() }
        if strip.exists { strip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).press(forDuration: 1.2); sleep(1) }
        shot("longpress-strip-top", tree: true)
        if element("Размер и деление").exists {
            app.swipeUp(); shot("meter-sheet-scrolled", tree: true)
            tap("Закрыть")
        } else { dismissByDim() }
        // presets
        tapBegins("Пресет:"); sleep(1); shot("presets", tree: true)
        tapIfExists("Сохранить текущие"); sleep(1); shot("preset-name", tree: true)
        tapIfExists("Сохранить"); sleep(1); shot("preset-saved", tree: true)
        tapIfExists("Закрыть"); sleep(1); shot("after-presets", tree: true)
    }

    func testModesTimerSounds() {
        launch(["-tab", "metronome"])
        element("Темп").press(forDuration: 1.2); sleep(1)
        tap("Разгон"); sleep(1)
        tap("Готово"); sleep(1)
        shot("after-ramp-set", tree: true)
        tap("Старт"); sleep(4); shot("ramp-playing", tree: true)
        tap("Стоп"); shot("ramp-stopped", tree: true)
        // chips now visible?
        let chips = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Разгон'")).firstMatch
        if chips.exists { safeTap(chips); sleep(1); shot("chip-tapped", tree: true); tapIfExists("Закрыть") }
        // settings → sounds
        tap("Настройки"); sleep(1); shot("settings", tree: true)
        app.swipeUp(); shot("settings-scrolled", tree: true)
    }
}

final class FretboardMoreTests: TruverUITestCase {
    func testSearchMode() {
        launch(["-template", "g6-standard-e", "-tab", "fretboard"])
        tap("Поиск"); sleep(1); shot("search-empty", tree: true)
        let n = elementBegins("Гриф,")
        // E string open area: tap 4 frets on different strings
        for p in [(0.08, 0.35), (0.25, 0.35), (0.42, 0.2), (0.58, 0.35)] { n.coordinate(withNormalizedOffset: CGVector(dx: p.0, dy: p.1)).tap(); usleep(500_000) }
        shot("search-marked", tree: true)
        let res = app.buttons.matching(NSPredicate(format: "label CONTAINS 'гамм' OR label CONTAINS 'ноты'")).firstMatch
        if res.exists { safeTap(res); sleep(1) }
        shot("search-results", tree: true)
        app.swipeUp(); shot("search-results-scrolled")
    }

    func testChordModeAndLibraryBack() {
        launch(["-template", "g6-standard-e", "-tab", "fretboard"])
        tap("Аккорд"); sleep(1); shot("chord-6str", tree: true)
        tap("Следующее расположение"); shot("chord-next")
        tap("Все аккорды"); sleep(1)
        tapIfExists("Назад"); sleep(1); shot("library-back", tree: true)
        tapIfExists("Гаммы ›"); sleep(1); shot("chord-scales-link", tree: true)
    }

    func testPathExitAndPause() {
        launch(["-template", "g6-standard-e", "-tab", "fretboard"])
        let n = elementBegins("Гриф,")
        n.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.3)).press(forDuration: 1.0); sleep(1)
        tap("Путь отсюда"); sleep(1)
        shot("path", tree: true)
        tap("Сыграть путь"); sleep(3); shot("path-playing-3s", tree: true)
        tap("Пауза"); shot("path-paused", tree: true)
        tap("Сыграть путь"); usleep(800_000); shot("path-resumed", tree: true)
        tapIfExists("Пауза")
        tap("Гамма"); sleep(1); shot("tap-scale-segment-in-path", tree: true)
    }
}
