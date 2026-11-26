import XCTest

final class PracticeSettingsTests: TruverUITestCase {
    func testPracticeAfterMetronome() {
        launch(["-tab", "practice"]); app.tap(); sleep(1)
        shot("practice-empty", tree: true)
        tab("Метроном"); tap("Старт"); sleep(8); tap("Стоп")
        tab("Занятия"); sleep(1)
        shot("practice-after-8s", tree: true)
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Метроном'")).firstMatch
        if row.exists { row.tap(); sleep(1) }
        shot("practice-row-tapped", tree: true)
    }

    func testSettings() {
        launch(["-tab", "tuner"]); app.tap(); sleep(1)
        tap("Настройки"); sleep(1)
        shot("settings", tree: true)
        app.swipeUp(); shot("settings-scrolled", tree: true)
        app.swipeDown()
        for page in ["Обозначение нот", "A4 по умолчанию", "Вход", "Громкость", "О Truver"] {
            if tapIfExists(page) {
                sleep(1); shot("page-\(page)", tree: true)
                if page == "Обозначение нот" { tapIfExists("Немецкое"); shot("german") ; tapIfExists("Международное") }
                tapIfExists("Назад") || tapIfExists("Готово") || tapIfExists("Закрыть")
                sleep(1)
            }
        }
        shot("settings-end", tree: true)
        tapIfExists("Назад") || tapIfExists("Закрыть")
        sleep(1); shot("closed-settings")
    }
}
