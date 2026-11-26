import XCTest

final class OnboardingTests: TruverUITestCase {
    func testFirstLaunch() {
        launch([], skipOnboarding: false)
        shot("welcome", tree: true)
        tap("Начать")
        shot("tour", tree: true)
        tap("Пропустить")   // «Знакомство» (Features/Tour) between the welcome and the instrument
        shot("instrument-step", tree: true)
        // choose 8 strings: tap "Больше" twice
        tapIfExists("Больше"); tapIfExists("Больше")
        shot("instrument-8-strings", tree: true)
        app.swipeUp(); usleep(500_000)
        shot("instrument-scrolled")
        tap("Продолжить")
        shot("mic-step", tree: true)
        tap("Продолжить")
        sleep(2)
        shot("after-mic-continue")
        app.tap() // fires interruption monitor
        sleep(2)
        shot("tuner-after-onboarding", tree: true)
    }

    func testSkip() {
        launch([], skipOnboarding: false)
        tap("Начать")
        tap("Пропустить")   // «Знакомство»
        tap("Пропустить — гитара 6 струн, стандарт E")
        shot("after-skip", tree: true)
        tapIfExists("Продолжить")
        sleep(1); app.tap(); sleep(1)
        shot("tuner-after-skip")
    }
}
