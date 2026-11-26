import XCTest

/// Fret count: chosen at the first launch, kept when another guitar template is picked, the neck ends there.
final class FretCountTests: TruverUITestCase {
    func testOnboardingFrets() {
        launch(["-onboardingStep", "1"], skipOnboarding: false)
        sleep(1)
        shot("instrument-step", tree: true)
        tap("22"); sleep(1)
        shot("frets-22", tree: true)
        tap("Продолжить"); sleep(1)
        tapIfExists("Продолжить"); sleep(2)
        tapIfExists("Разрешить"); sleep(1)
        tap("Гриф"); sleep(1)
        tapBegins("Вид грифа"); sleep(1)
        tapIfExists("Весь гриф"); sleep(2)
        shot("neck-22", tree: true)
    }
}
