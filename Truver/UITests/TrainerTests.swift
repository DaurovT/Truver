import XCTest

/// FB-12: the trainer opens from «Занятия», answers move on, the series ends with a summary.
final class TrainerTests: TruverUITestCase {
    func testNameNoteSeries() {
        launch(["-template", "g8-standard-fs", "-tab", "practice"])
        shot("practice-card", tree: true)
        tapBegins("Тренажёр грифа"); sleep(2)
        tapIfExists("Назови ноту"); sleep(1)
        shot("trainer-question", tree: true)
        // Always «C»: some answers are right, most wrong — the series must still finish.
        for i in 0..<20 {
            let c = app.buttons.matching(NSPredicate(format: "label == 'C'")).firstMatch
            guard c.waitForExistence(timeout: 3) else { break }
            c.tap()
            if i == 0 { usleep(300_000); shot("trainer-feedback") }
            sleep(1); usleep(300_000)
        }
        sleep(1)
        shot("trainer-summary", tree: true)
        tapIfExists("Закрыть"); sleep(1)
        shot("practice-after", tree: true)
    }
}
