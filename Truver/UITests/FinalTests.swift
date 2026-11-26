import XCTest

final class FinalTests: TruverUITestCase {
    func testRebuildAndCapo() {
        launch(["-template", "g7-standard-b"])
        tapBegins("Строй:"); sleep(1)
        tap("7-струнная гитара"); sleep(1)
        let plus = app.buttons.matching(NSPredicate(format: "label == 'Больше'")).firstMatch
        safeTap(plus); sleep(1)
        shot("rebuild-sheet", tree: true)
        app.swipeUp(); shot("rebuild-scrolled")
        tapIfExists("Пересобрать"); sleep(1)
        shot("after-rebuild", tree: true)
        if !element("Инструмент").exists { tapBegins("Строй:"); sleep(1); tapBegins("8-струнная") ; sleep(1) }
        tapIfExists("Капо"); sleep(1); shot("capo-menu", tree: true)
        tapIfExists("3-й лад"); sleep(1); shot("capo-3", tree: true)
        tapIfExists("Готово"); sleep(1); tapIfExists("Закрыть"); sleep(1)
        tab("Гриф"); sleep(1); shot("fretboard-capo3", tree: true)
        tab("Тюнер"); sleep(1); shot("tuner-capo3", tree: true)
    }

    func testMeterFromSettingsAndLefty() {
        launch(["-template", "g6-standard-e", "-tab", "metronome"])
        tap("Настройки"); sleep(1)
        tap("Размер и деление"); sleep(1)
        shot("meter-from-settings", tree: true)
        app.swipeUp(); shot("meter-scrolled", tree: true)
        tapIfExists("Закрыть") || tapIfExists("Готово") || tapIfExists("Назад"); sleep(1)
        shot("after-meter-close", tree: true)
        tapIfExists("Назад"); sleep(1)
        tab("Гриф"); sleep(1)
        tap("Вид и подписи"); sleep(1)
        let lefty = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Для левши'"))
        if lefty.count > 0 { safeTap(lefty.element(boundBy: lefty.count - 1)); sleep(1) }
        shot("lefty-toggled", tree: true)
        tap("Закрыть"); sleep(1); shot("fretboard-lefty", tree: true)
    }
}
