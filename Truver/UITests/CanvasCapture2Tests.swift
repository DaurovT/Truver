import XCTest

/// Second batch for the canvas page «Приложение · как сейчас»: states and sheets the first batch left out.
final class CanvasCapture2Tests: TruverUITestCase {
    func cap(_ name: String, _ args: [String], wait: UInt32 = 3, onboarding: Bool = false, _ actions: (() -> Void)? = nil) {
        XCUIDevice.shared.orientation = .portrait
        launch(args, skipOnboarding: !onboarding)
        sleep(wait)
        actions?()
        shot(name)
        app.terminate()
    }

    func testA_TunerStates() {
        let t = ["-template", "g6-standard-e", "-tab", "tuner"]
        for demo in ["listening", "waiting", "sharp", "chromatic", "manual", "done", "reference", "outOfRange", "noAccess"] {
            cap("tuner-\(demo)", t + ["-tunerDemo", demo])
        }
        cap("tuner-large", t + ["-tunerDemo", "flat", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
    }

    func testB_Tunings() {
        let t = ["-template", "g6-standard-e", "-tab", "tuner"]
        cap("tunings-library", t + ["-sheet", "library"])
        cap("tunings-template", t + ["-sheet", "templateCard"])
        cap("tunings-generator", t + ["-sheet", "generator"])
        cap("tunings-add", t + ["-sheet", "tuningsAdd"])
        cap("tunings-rebuild", t + ["-sheet", "instrumentRebuild"])
    }

    func testC_Fret() {
        let f = ["-template", "g8-standard-fs", "-tab", "fretboard"]
        cap("fret-chords-from-note", f + ["-sheet", "chordsFromNote"])
        cap("fret-scale-from-note", f + ["-sheet", "scaleFromNote"])
        cap("fret-search-results", f + ["-fretMode", "search", "-sheet", "searchResults"])
        cap("fret-progression-sheet", f + ["-fretMode", "progression", "-sheet", "fretProgression"])
        cap("fret-progression-chord", f + ["-fretMode", "progression", "-sheet", "progressionChord"])
    }

    func testD_Metro() {
        let m = ["-template", "g8-standard-fs", "-tab", "metronome"]
        cap("metro-playing", m + ["-metroDemo", "-metroPlay"], wait: 5)
        cap("metro-speedup", m + ["-sheet", "metroParams"])
        cap("metro-timer", m + ["-sheet", "metroTimer"])
    }

    func testE_PracticeSettingsOnboarding() {
        let p = ["-template", "g8-standard-fs", "-tab", "practice"]
        cap("practice-trainer-play", p + ["-sheet", "trainerPlay"])
        cap("practice-trainer-summary", p + ["-sheet", "trainerName"], wait: 2) {
            for _ in 0..<20 {
                let c = self.app.buttons.matching(NSPredicate(format: "label == 'C'")).firstMatch
                guard c.waitForExistence(timeout: 3) else { break }
                c.tap(); sleep(1); usleep(300_000)
            }
            sleep(1)
        }
        cap("practice-session-running", p) {
            self.tapBegins("Занятие"); sleep(2)
            for label in ["Проверка игры", "Голосовые подсказки"] {
                let sw = self.app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label))
                if sw.count > 0 { self.safeTap(sw.element(boundBy: sw.count - 1)); sleep(1) }
            }
            self.tapIfExists("Начать занятие"); sleep(3)
        }
        cap("settings-notation", ["-tab", "tuner", "-settingsPage", "notation"])
        cap("settings-a4", ["-tab", "tuner", "-settingsPage", "a4"])
        cap("settings-about", ["-tab", "tuner", "-settingsPage", "about"])
        cap("onboarding-welcome", ["-onboardingStep", "0"], onboarding: true)
        cap("onboarding-mic", ["-onboardingStep", "2"], onboarding: true)
    }

    func testF_Landscape() {
        func land(_ name: String, _ args: [String]) {
            launch(args)
            XCUIDevice.shared.orientation = .landscapeLeft
            sleep(4)
            shot(name)
            XCUIDevice.shared.orientation = .portrait
            app.terminate()
        }
        land("land-fret-chord", ["-template", "g8-standard-fs", "-tab", "fretboard", "-fretMode", "chord"])
        land("land-fret-position", ["-template", "g8-standard-fs", "-tab", "fretboard"])
        land("land-fret-progression", ["-template", "g8-standard-fs", "-tab", "fretboard", "-fretMode", "progression"])
    }
}
